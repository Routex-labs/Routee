package com.navigation.navigation_client

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** gyro heading을 rotation vector 쪽으로 끌어오는 시정수(초). 근거는 docs/client/android-heading-drift.md. */
private const val GYRO_REANCHOR_TAU_SECONDS = 45.0

/** gyro hold에 **들어가는** innovation 문턱(도). */
private const val GYRO_HOLD_ENTER_DEG = 35.0

/** gyro hold에서 **나오는** innovation 문턱(도). 진입보다 낮아야 경계에서 안 떤다. */
private const val GYRO_HOLD_RELEASE_DEG = 15.0

/** gyro hold를 붙들 수 있는 최대 시간(ns). 넘으면 rotation vector로 강제 재잠금. */
private const val GYRO_HOLD_MAX_NANOS = 8_000_000_000L

/** 전방 벡터의 수평 성분이 이보다 커야 heading을 읽을 수 있다(iOS와 같은 값). */
private const val HEADING_HORIZONTAL_MIN = 0.4

/**
 * Android SensorManager -> typed Dart PDR boundary.
 *
 * STEP_COUNTER is the only confirmed-count authority after it becomes
 * available. STEP_DETECTOR and acceleration peaks remain timing/cadence
 * diagnostics; they must never independently extend the confirmed path.
 */
class PdrMotionBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler, MethodChannel.MethodCallHandler, SensorEventListener {
    private val sensorManager = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val roninEstimator = RoninStrideEstimator(activity.applicationContext)
    private var sink: EventChannel.EventSink? = null

    private val rotationMatrix = FloatArray(9)
    private val orientation = FloatArray(3)
    private val gravity = FloatArray(3)
    private val linearAccel = FloatArray(3)
    private val rawAccel = FloatArray(3)
    private val gyro = FloatArray(3)
    private var hasRotation = false
    private var hasGravity = false
    private var hasLinearAccel = false
    private var hasGyro = false
    private var rotationSource = "unavailable"

    private var rawRotationHeadingDeg = 0.0
    private var fusedHeadingDeg = 0.0
    private var gyroHeadingDeg = 0.0
    private var gyroHeadingInitialized = false

    // 마지막 rotation vector 표본이 수평 게이트를 통과했는가. 통과 못 했으면
    // rawRotationHeadingDeg는 그때 그대로 멈춰 있는 옛 값이다 — iOS는 그 구간을
    // headingStable=false로 알리는데 Android만 알리지 않고 있었다.
    private var rawRotationHeadingFresh = false

    // 연속 재앵커링에 쓰는 직전 rotation 표본 시각. 0이면 아직 기준이 없다.
    private var lastRotationNs = 0L

    // 지금 gyro hold 중인가. 진입·해제 문턱이 다르므로(히스테리시스) 상태가 필요하다.
    private var gyroHoldActive = false
    private var gyroHoldStartedNs = 0L
    private var selectedHeadingSource = "unavailable"
    private var deviceHeadingDeg = -1.0
    private var yawDeg = 0.0
    private var pitchDeg = 0.0
    private var rollDeg = 0.0
    private var headingStable = false
    private var rotationHeadingAccuracyDeg = -1.0
    private var magneticAccuracy = "unknown"
    private var magneticField = 0.0
    private var magneticFieldBaseline: Double? = null
    private var accelMagnitude = 0.0
    private var gyroZ = 0.0
    private var motionTimestampMs = 0.0
    private var motionHz = 0.0
    private var lastImuSensorNs = 0L
    private var lastGyroNs = 0L
    private var lastMotionEmitMs = 0.0

    private var stepSessionId = 0
    private var sessionStartMs = System.currentTimeMillis().toDouble()
    private var rawStepCounter: Float? = null
    private var stepCounterBaseline: Float? = null
    private var observedCounterSteps = 0
    private var observedCounterDelta = 0
    private var lastStepCounterAtMs = 0.0
    private var stepCounterReady = false
    private var counterLiveMode = false
    private var sessionFinalized = false
    private var steps = 0
    private var lastReportedSteps = 0
    private var detectorSteps = 0
    private var stepDetectorEvents = 0
    private var lastPedometerAtMs = 0.0
    private var lastPedometerEventAtMs = 0.0
    private var pedometerDeltaMs = 0.0
    private var cadenceHz = 0.0
    private var cadenceAvailable = false
    private var roninCadenceHz = 0.0
    private var lastStepAccelAmplitudeMps2 = 0.0
    private var latestStepEventSource = "snapshot"

    // Peaks are timestamps only. They reconstruct heading timing for a
    // counter batch; they are deliberately not a second confirmed count.
    private val accelPeakTimes = ArrayList<Double>()
    private val detectorStepTimes = ArrayList<Double>()
    private var stepPeakCount = 0
    private var latestStepPeakMs = 0.0
    private var peakArmed = true
    private var lastPeakMs = 0.0
    private var envelopeInitialized = false
    private var envelopeMax = 0.0
    private var envelopeMin = 0.0
    private var stepWindowInitialized = false
    private var stepWindowMinG = 0.0
    private var stepWindowMaxG = 0.0

    // 기압계. 층 전이 판정 전용이고 PDR 걸음·heading 경로에는 개입하지 않는다.
    // TYPE_PRESSURE 미탑재 기기가 실제로 있으므로 가용 여부를 Dart로 알린다.
    private var barometerAvailable = false
    private var barometerName = "unavailable"
    private var hasPressureSample = false
    private var pressureHpa = 0.0
    private var pressureTimestampMs = 0.0
    private var lastPressureEmitMs = 0.0

    private data class HorizontalSample(val bootSeconds: Double, val east: Double, val north: Double)
    private val horizontalSamples = ArrayList<HorizontalSample>()
    private var walkDirDeg = 0.0
    private var walkDirConfidence = 0.0

    init {
        EventChannel(messenger, "navigation_client/pdr_motion").setStreamHandler(this)
        MethodChannel(messenger, "navigation_client/pdr_motion_cmd").setMethodCallHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        startSensors()
        emit("snapshot")
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        roninEstimator.resetSession()
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resetPedometer" -> result.success(resetPedometer())
            "finalizePedometer" -> result.success(finalizePedometer())
            else -> result.notImplemented()
        }
    }

    private fun startSensors() {
        sensorManager.unregisterListener(this)
        val rotation = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sensorManager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
        rotationSource = when (rotation?.type) {
            Sensor.TYPE_ROTATION_VECTOR -> "sensor_manager/rotation_vector"
            Sensor.TYPE_GAME_ROTATION_VECTOR -> "sensor_manager/game_rotation_vector"
            else -> "unavailable"
        }
        register(rotation, 10_000)
        register(sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION), 10_000)
        // RoNIN 원 모델의 200Hz 입력에 최대한 가까운 raw 표본을 확보한다.
        // 실제 기기 전달률이 낮거나 흔들려도 estimator가 200Hz로 보간하며,
        // 40ms보다 큰 결손이 있으면 그 추론 창을 폐기한다.
        register(sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER), 5_000)
        register(sensorManager.getDefaultSensor(Sensor.TYPE_GRAVITY), 10_000)
        register(sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE), 5_000)
        register(sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD), 20_000)
        // 기압은 층 전이 판정에만 쓰므로 5Hz면 충분하다(에스컬레이터 상승은 20~30초).
        // 더 빠르게 받으면 이벤트 수만 늘고 판정 품질은 나아지지 않는다.
        val pressure = sensorManager.getDefaultSensor(Sensor.TYPE_PRESSURE)
        barometerAvailable = pressure != null
        barometerName = pressure?.name ?: "unavailable"
        register(pressure, 200_000)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(activity, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
        ) {
            register(sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER), SensorManager.SENSOR_DELAY_NORMAL)
            register(sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR), SensorManager.SENSOR_DELAY_FASTEST)
        }
    }

    private fun register(sensor: Sensor?, periodUs: Int) {
        if (sensor != null) sensorManager.registerListener(this, sensor, periodUs)
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR, Sensor.TYPE_GAME_ROTATION_VECTOR -> updateRotation(event)
            Sensor.TYPE_LINEAR_ACCELERATION -> {
                copy3(event.values, linearAccel)
                hasLinearAccel = true
                captureImu(event.timestamp)
            }
            Sensor.TYPE_ACCELEROMETER -> {
                copy3(event.values, rawAccel)
                if (hasRotation && hasGyro) {
                    roninEstimator.addDeviceSample(
                        event.timestamp,
                        gyro,
                        rawAccel,
                        rotationMatrix,
                    )
                }
                if (!hasLinearAccel) captureImu(event.timestamp)
            }
            Sensor.TYPE_GRAVITY -> {
                copy3(event.values, gravity)
                hasGravity = true
            }
            Sensor.TYPE_GYROSCOPE -> updateGyro(event)
            Sensor.TYPE_MAGNETIC_FIELD -> magneticField = magnitude(event.values)
            Sensor.TYPE_STEP_COUNTER -> updateStepCounter(event.values[0], event.timestamp)
            Sensor.TYPE_STEP_DETECTOR -> updateStepDetector(event.timestamp)
            Sensor.TYPE_PRESSURE -> updatePressure(event.values[0], event.timestamp)
        }
    }

    private fun updateRotation(event: SensorEvent) {
        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
        SensorManager.getOrientation(rotationMatrix, orientation)
        hasRotation = true
        rotationHeadingAccuracyDeg = event.values.getOrNull(4)?.toDouble()?.takeIf { it >= 0 }
            ?.let { Math.toDegrees(it) } ?: -1.0

        // +Y(top) is the usual forward axis. When upright, smoothly use the
        // rear-camera (-Z) direction so portrait and held-flat walks agree.
        val topUp = rotationMatrix[7].toDouble()
        val cameraWeight = ((topUp - 0.5) / 0.37).coerceIn(0.0, 1.0)
        val forwardEast = rotationMatrix[1].toDouble() - cameraWeight * rotationMatrix[2]
        val forwardNorth = rotationMatrix[4].toDouble() - cameraWeight * rotationMatrix[5]
        rawRotationHeadingFresh =
            sqrt(forwardEast * forwardEast + forwardNorth * forwardNorth) > HEADING_HORIZONTAL_MIN
        if (rawRotationHeadingFresh) {
            rawRotationHeadingDeg = normalizeDegrees(Math.toDegrees(atan2(forwardEast, forwardNorth)))
            deviceHeadingDeg = rawRotationHeadingDeg
            if (gyroHeadingInitialized) {
                reanchorGyroHeading(event.timestamp)
            } else {
                gyroHeadingDeg = rawRotationHeadingDeg
                gyroHeadingInitialized = true
                lastRotationNs = event.timestamp
            }
        }
        yawDeg = normalizeDegrees(Math.toDegrees(orientation[0].toDouble()))
        pitchDeg = Math.toDegrees(orientation[1].toDouble())
        rollDeg = Math.toDegrees(orientation[2].toDouble())
    }

    /**
     * gyro 적분 heading을 rotation vector 쪽으로 아주 천천히(τ≈45s) 끌어온다.
     *
     * **hold 여부와 무관하게 매 rotation 표본마다 돈다.** 세션당 한 번만 앵커링하면
     * 잔류 bias가 무제한 누적되는데, hold의 해제 조건(innovation)이 바로 그
     * gyroHeading을 입력으로 쓴다 — 드리프트가 스스로 해제 조건을 키워 hold가
     * 영구 래치가 된다. 시정수가 커서 한 표본이 옮기는 양은 걸음 회전에 묻히고,
     * 자기 교란 구간(hold)에서 끌려가는 총량도 상한 시간만큼으로 묶인다.
     */
    private fun reanchorGyroHeading(sensorNs: Long) {
        val previousNs = lastRotationNs
        lastRotationNs = sensorNs
        if (previousNs == 0L) return
        val dt = (sensorNs - previousNs) / 1_000_000_000.0
        // 앱이 백그라운드에 있다 돌아온 구간은 한 번에 끌어당기지 않는다.
        if (dt <= 0.0 || dt > 0.5) return
        val gain = 1.0 - exp(-dt / GYRO_REANCHOR_TAU_SECONDS)
        gyroHeadingDeg = normalizeDegrees(
            gyroHeadingDeg + gain * shortestAngleDelta(rawRotationHeadingDeg, gyroHeadingDeg),
        )
    }

    private fun updateGyro(event: SensorEvent) {
        copy3(event.values, gyro)
        hasGyro = true
        gyroZ = gyro[2].toDouble()
        if (lastGyroNs != 0L && gyroHeadingInitialized) {
            val dt = (event.timestamp - lastGyroNs) / 1_000_000_000.0
            if (dt in 0.0..0.5) {
                val g = if (hasGravity) gravity else floatArrayOf(0f, 0f, SensorManager.GRAVITY_EARTH)
                val gMagnitude = magnitude(g)
                if (gMagnitude > 0) {
                    val rate = (gyro[0] * g[0] + gyro[1] * g[1] + gyro[2] * g[2]) / gMagnitude
                    gyroHeadingDeg = normalizeDegrees(gyroHeadingDeg - Math.toDegrees(rate * dt))
                }
            }
        }
        lastGyroNs = event.timestamp
    }

    private fun captureImu(sensorNs: Long) {
        if (!hasRotation) return
        val epochMs = sensorNsToEpochMs(sensorNs)
        val user = if (hasLinearAccel) linearAccel else {
            val g = if (hasGravity) gravity else floatArrayOf(0f, 0f, SensorManager.GRAVITY_EARTH)
            floatArrayOf(rawAccel[0] - g[0], rawAccel[1] - g[1], rawAccel[2] - g[2])
        }
        val userXG = user[0] / SensorManager.GRAVITY_EARTH
        val userYG = user[1] / SensorManager.GRAVITY_EARTH
        val userZG = user[2] / SensorManager.GRAVITY_EARTH
        val worldEast = rotationMatrix[0] * userXG + rotationMatrix[1] * userYG + rotationMatrix[2] * userZG
        val worldNorth = rotationMatrix[3] * userXG + rotationMatrix[4] * userYG + rotationMatrix[5] * userZG
        accelMagnitude = sqrt(userXG * userXG + userYG * userYG + userZG * userZG).toDouble()
        if (!stepWindowInitialized) {
            stepWindowInitialized = true
            stepWindowMinG = accelMagnitude
            stepWindowMaxG = accelMagnitude
        } else {
            stepWindowMinG = min(stepWindowMinG, accelMagnitude)
            stepWindowMaxG = max(stepWindowMaxG, accelMagnitude)
        }
        motionTimestampMs = epochMs
        if (lastImuSensorNs != 0L) {
            val dt = (sensorNs - lastImuSensorNs) / 1_000_000_000.0
            if (dt > 0) {
                val hz = 1.0 / dt
                motionHz = if (motionHz == 0.0) hz else motionHz * 0.9 + hz * 0.1
            }
        }
        lastImuSensorNs = sensorNs

        selectHeading()
        updateWalkingDirection(sensorNs / 1_000_000_000.0, worldEast.toDouble(), worldNorth.toDouble())
        detectPeak(accelMagnitude, epochMs)
        if (epochMs - lastMotionEmitMs >= 30.0) {
            lastMotionEmitMs = epochMs
            emit("motion")
        }
    }

    /** A short gyro hold avoids a sudden magnetic jump; healthy rotation-vector
     * values relock immediately. SensorManager still supplies the base fusion.
     * 진입·해제 문턱과 상한 시간의 근거는 docs/client/android-heading-drift.md. */
    private fun selectHeading() {
        // **baseline은 hold 밖에서 갱신한다.** 예전에는 hold가 아닐 때만 갱신해서,
        // hold에 들어간 순간 기준값이 얼어붙었다 — 자기장이 정상으로 돌아와도
        // fieldDeviation이 옛 기준과 비교돼 0.35 아래로 못 내려오고, hold가
        // 자기 자신의 해제를 막는 래치가 됐다.
        if (magneticField > 1) {
            magneticFieldBaseline = (magneticFieldBaseline ?: magneticField) * 0.985 + magneticField * 0.015
        }
        val baseline = magneticFieldBaseline
        val fieldDeviation = if (baseline != null && baseline > 1 && magneticField > 1) {
            abs(magneticField - baseline) / baseline
        } else 0.0
        val innovation = angularDistance(rawRotationHeadingDeg, gyroHeadingDeg)
        val poorMagnetic = magneticAccuracy == "low" || magneticAccuracy == "uncalibrated"
        val inaccurate = rotationHeadingAccuracyDeg > 35
        // 진입 35°, 해제 15°. 한 값이면 문턱 근처에서 표본마다 hold가 뒤집혀
        // heading이 두 값 사이를 오간다.
        val innovationHigh = innovation >
            if (gyroHoldActive) GYRO_HOLD_RELEASE_DEG else GYRO_HOLD_ENTER_DEG
        val gameRotationVector = rotationSource.contains("game_rotation_vector")
        var useGyroHold = gameRotationVector || poorMagnetic ||
            fieldDeviation > 0.35 || innovationHigh || inaccurate
        // 마지막 안전장치. 위 조건이 무엇이든 8초를 넘겨 붙들지 않는다 — 조건
        // 하나가 다시 래치가 되어도 여기서 끊긴다. **game rotation vector는 뺀다**:
        // 그쪽은 자력계를 안 써서 재잠금할 절대 북 자체가 없고, 그 hold는 고장이
        // 아니라 설계다.
        if (useGyroHold && gyroHoldActive && !gameRotationVector &&
            rawRotationHeadingFresh &&
            SystemClock.elapsedRealtimeNanos() - gyroHoldStartedNs > GYRO_HOLD_MAX_NANOS
        ) {
            gyroHeadingDeg = rawRotationHeadingDeg
            useGyroHold = false
        }
        if (useGyroHold && gyroHeadingInitialized) {
            if (!gyroHoldActive) {
                gyroHoldActive = true
                gyroHoldStartedNs = SystemClock.elapsedRealtimeNanos()
            }
            fusedHeadingDeg = gyroHeadingDeg
            // TYPE_ROTATION_VECTOR는 자력계까지 포함한 9-axis fusion이라
            // gyro hold 중에도 마지막 절대 북 기준 frame을 이어받는다. hold는
            // "정확도가 낮다"는 뜻이지, heading frame 자체가 arbitrary로
            // 바뀐다는 뜻은 아니다. 반대로 game rotation vector는 처음부터
            // 자력계를 쓰지 않으므로 기존처럼 absolute heading으로 선언하지
            // 않는다.
            selectedHeadingSource = if (rotationSource.contains("rotation_vector") &&
                !rotationSource.contains("game")) {
                "sensor_manager/rotation_vector+gyro_hold"
            } else {
                "sensor_manager/gyro_hold"
            }
            headingStable = false
            return
        }
        gyroHoldActive = false
        fusedHeadingDeg = rawRotationHeadingDeg
        selectedHeadingSource = rotationSource
        // **기울기 게이트를 iOS와 맞춘다.** 폰을 눕히면 전방 벡터의 수평 성분이
        // 사라져 rawRotationHeadingDeg가 마지막 값에 얼어붙는데, 예전에는 그
        // 구간에서도 stable=true였다. 공용 코어가 이 값으로 smoothing 시정수를
        // 0.6s/0.1s로 가르므로(packages/indoor_pdr_core/lib/src/application/
        // pdr_session.dart), Android만 멈춘 값을 빠른 시정수로 따라갔다.
        headingStable = rotationSource.contains("rotation_vector") &&
            !rotationSource.contains("game") &&
            rawRotationHeadingFresh
    }

    private fun updateStepCounter(value: Float, sensorNs: Long) {
        rawStepCounter = value
        if (sessionFinalized) return
        if (stepCounterBaseline == null) stepCounterBaseline = value
        val counterSteps = max(0, (value - (stepCounterBaseline ?: value)).toInt())
        observedCounterDelta = max(0, counterSteps - observedCounterSteps)
        observedCounterSteps = counterSteps
        lastStepCounterAtMs = sensorNsToEpochMs(sensorNs)
        if (counterSteps <= 0) return
        stepCounterReady = true
        counterLiveMode = true
        if (counterSteps > steps) {
            steps = counterSteps
            latestStepEventSource = "step_counter+accel_timestamps"
            lastPedometerEventAtMs = lastStepCounterAtMs
            emit("pedometer")
        }
    }

    private fun updateStepDetector(sensorNs: Long) {
        if (sessionFinalized) return
        val atMs = sensorNsToEpochMs(sensorNs)
        stepDetectorEvents += 1
        val monotonicAtMs = if (lastPedometerAtMs > 0) max(atMs, lastPedometerAtMs + 0.001) else atMs
        pedometerDeltaMs = if (lastPedometerAtMs > 0) monotonicAtMs - lastPedometerAtMs else 0.0
        if (pedometerDeltaMs in 200.0..3_000.0) {
            cadenceHz = 1_000.0 / pedometerDeltaMs
            cadenceAvailable = true
            roninCadenceHz = if (roninCadenceHz <= 0) {
                cadenceHz
            } else {
                roninCadenceHz * 0.8 + cadenceHz * 0.2
            }
        }
        lastPedometerAtMs = monotonicAtMs
        detectorSteps += 1
        detectorStepTimes.add(atMs)
        detectorStepTimes.removeAll { it < atMs - 20_000.0 }
        lastStepAccelAmplitudeMps2 = if (stepWindowInitialized) {
            max(0.0, stepWindowMaxG - stepWindowMinG) * SensorManager.GRAVITY_EARTH
        } else 0.0
        stepWindowMinG = accelMagnitude
        stepWindowMaxG = accelMagnitude
        stepWindowInitialized = true
        if (!counterLiveMode) {
            steps = detectorSteps
            latestStepEventSource = "step_detector_fallback"
            lastPedometerEventAtMs = atMs
            emit("pedometer")
        }
    }

    /** TYPE_PRESSURE values[0]은 hPa다. registerListener의 주기는 힌트일 뿐이라
     * 기기가 더 빨리 밀어 넣을 수 있으므로 발신 간격을 코드에서 한 번 더 조인다. */
    private fun updatePressure(hpa: Float, sensorNs: Long) {
        pressureHpa = hpa.toDouble()
        pressureTimestampMs = sensorNsToEpochMs(sensorNs)
        hasPressureSample = true
        if (pressureTimestampMs - lastPressureEmitMs < 180.0) return
        lastPressureEmitMs = pressureTimestampMs
        emitAltitude()
    }

    /**
     * 기압 샘플만 담은 이벤트. emit()을 재사용하지 않는다 — emit()은
     * kind != "motion"에서 pedometer 블록을 함께 싣고 lastReportedSteps 델타
     * 회계를 진행시키므로, 초당 몇 번 오는 기압 이벤트에 태우면 걸음 델타가
     * 0으로 잘려 나가며 PDR 배치 타이밍이 흔들린다.
     */
    private fun emitAltitude() {
        val eventSink = sink ?: return
        if (!hasPressureSample) return
        val payload = linkedMapOf<String, Any>(
            "source" to "android_sensor_manager",
            "kind" to "altitude",
            "stepSessionId" to stepSessionId,
            "altimeterAvailable" to barometerAvailable,
            "altimeterSource" to "android_pressure",
            "altimeterSensorName" to barometerName,
            "pressureHpa" to pressureHpa,
            "altitudeTimestamp" to pressureTimestampMs,
        )
        activity.runOnUiThread { eventSink.success(payload) }
    }

    private fun resetPedometer(): Int {
        stepSessionId += 1
        sessionStartMs = System.currentTimeMillis().toDouble()
        stepCounterBaseline = rawStepCounter
        observedCounterSteps = 0
        observedCounterDelta = 0
        lastStepCounterAtMs = 0.0
        stepCounterReady = false
        counterLiveMode = false
        sessionFinalized = false
        steps = 0
        lastReportedSteps = 0
        detectorSteps = 0
        stepDetectorEvents = 0
        lastPedometerAtMs = 0.0
        lastPedometerEventAtMs = 0.0
        pedometerDeltaMs = 0.0
        cadenceHz = 0.0
        cadenceAvailable = false
        roninCadenceHz = 0.0
        lastStepAccelAmplitudeMps2 = 0.0
        latestStepEventSource = "snapshot"
        accelPeakTimes.clear()
        detectorStepTimes.clear()
        stepPeakCount = 0
        latestStepPeakMs = 0.0
        peakArmed = true
        lastPeakMs = 0.0
        envelopeInitialized = false
        stepWindowInitialized = false
        horizontalSamples.clear()
        walkDirConfidence = 0.0
        gyroHeadingInitialized = false
        rawRotationHeadingFresh = false
        lastRotationNs = 0L
        gyroHoldActive = false
        gyroHoldStartedNs = 0L
        magneticFieldBaseline = null
        roninEstimator.resetSession()
        emit("snapshot")
        return stepSessionId
    }

    private fun finalizePedometer(): Map<String, Any> {
        val stoppedAtMs = System.currentTimeMillis().toDouble()
        if (stepCounterReady && observedCounterSteps > steps) {
            steps = observedCounterSteps
            latestStepEventSource = "step_counter+accel_timestamps"
            lastPedometerEventAtMs = if (lastStepCounterAtMs > 0) lastStepCounterAtMs else stoppedAtMs
        }
        sessionFinalized = true
        emit("snapshot")
        return linkedMapOf(
            "stepSessionId" to stepSessionId,
            "sessionStartMs" to sessionStartMs,
            "stoppedAtMs" to stoppedAtMs,
            "steps" to steps,
            "stepCounterSteps" to observedCounterSteps,
            "distanceAvailable" to false,
        )
    }

    private fun updateWalkingDirection(bootSeconds: Double, east: Double, north: Double) {
        horizontalSamples.add(HorizontalSample(bootSeconds, east, north))
        horizontalSamples.removeAll { it.bootSeconds < bootSeconds - 1.3 }
        if (horizontalSamples.size < 15) {
            walkDirConfidence = 0.0
            return
        }
        val meanEast = horizontalSamples.sumOf { it.east } / horizontalSamples.size
        val meanNorth = horizontalSamples.sumOf { it.north } / horizontalSamples.size
        var see = 0.0; var snn = 0.0; var sen = 0.0
        for (sample in horizontalSamples) {
            val e = sample.east - meanEast; val n = sample.north - meanNorth
            see += e * e; snn += n * n; sen += e * n
        }
        see /= horizontalSamples.size; snn /= horizontalSamples.size; sen /= horizontalSamples.size
        val trace = see + snn
        val disc = max(0.0, trace * trace / 4.0 - (see * snn - sen * sen))
        val l1 = trace / 2.0 + sqrt(disc)
        val l2 = trace / 2.0 - sqrt(disc)
        var vEast = sen; var vNorth = l1 - see
        if (abs(vEast) + abs(vNorth) < 1e-9) { vEast = l1 - snn; vNorth = sen }
        walkDirDeg = normalizeDegrees(Math.toDegrees(atan2(vEast, vNorth)))
        val anisotropy = if (l1 > 1e-9) (l1 - max(0.0, l2)) / l1 else 0.0
        walkDirConfidence = anisotropy * min(1.0, sqrt(trace) / 0.06)
    }

    private fun detectPeak(magnitude: Double, atMs: Double) {
        if (!envelopeInitialized) {
            envelopeInitialized = true; envelopeMax = magnitude; envelopeMin = magnitude
        } else {
            envelopeMax = if (magnitude > envelopeMax) magnitude else envelopeMax + 0.007 * (magnitude - envelopeMax)
            envelopeMin = if (magnitude < envelopeMin) magnitude else envelopeMin + 0.007 * (magnitude - envelopeMin)
        }
        val swing = envelopeMax - envelopeMin
        if (swing < 0.03) { peakArmed = true; return }
        val high = max(0.06, envelopeMin + 0.55 * swing)
        val low = envelopeMin + 0.30 * swing
        if (peakArmed && magnitude > high && atMs - lastPeakMs > 380.0) {
            accelPeakTimes.add(atMs)
            accelPeakTimes.removeAll { it < atMs - 20_000.0 }
            stepPeakCount += 1
            latestStepPeakMs = atMs
            lastPeakMs = atMs
            peakArmed = false
        } else if (magnitude < low) {
            peakArmed = true
        }
    }

    private fun emit(kind: String) {
        val eventSink = sink ?: return
        val payload = linkedMapOf<String, Any>(
            "source" to "android_sensor_manager",
            "kind" to kind,
            "stepSessionId" to stepSessionId,
        )
        if (kind == "snapshot") {
            // 첫 기압 샘플 전에도 Dart가 센서 유무를 알 수 있어야, 기압계 없는
            // 기기에서 층 전이 판정을 "대기 중"이 아니라 "비활성"으로 다룬다.
            payload["altimeterAvailable"] = barometerAvailable
            payload["altimeterSource"] =
                if (barometerAvailable) "android_pressure" else "unavailable"
            payload["altimeterSensorName"] = barometerName
        }
        if (kind != "pedometer" && hasRotation) {
            payload.putAll(linkedMapOf(
                "fusedHeadingDeg" to fusedHeadingDeg,
                "deviceHeadingDeg" to deviceHeadingDeg,
                "gyroHeadingDeg" to gyroHeadingDeg,
                "headingStable" to headingStable,
                "rotationHeadingAccuracyDeg" to rotationHeadingAccuracyDeg,
                "headingSource" to selectedHeadingSource,
                "yawDeg" to yawDeg, "pitchDeg" to pitchDeg, "rollDeg" to rollDeg,
                "magneticAccuracy" to magneticAccuracy, "magneticField" to magneticField,
                "walkDirDeg" to walkDirDeg, "walkDirConfidence" to walkDirConfidence,
                "motionTimestamp" to motionTimestampMs, "motionHz" to motionHz,
                "stepPeakCount" to stepPeakCount, "latestStepPeakMs" to latestStepPeakMs,
                "accelMagnitude" to accelMagnitude, "gyroZ" to gyroZ,
            ))
        }
        if (kind != "motion") {
            val reportedDelta = max(0, steps - lastReportedSteps)
            lastReportedSteps = steps
            val source = when {
                sessionFinalized && stepCounterReady -> "android_step_counter_final"
                counterLiveMode -> "android_step_counter_live"
                else -> "android_step_detector_fallback"
            }
            payload.putAll(linkedMapOf(
                "steps" to steps, "stepDelta" to reportedDelta,
                "stepCountSource" to source, "detectorSteps" to detectorSteps,
                "pedometerDistance" to 0.0, "pedometerDistanceAvailable" to false,
                "pedometerTimestamp" to lastPedometerEventAtMs, "pedometerDeltaMs" to pedometerDeltaMs,
                "pedometerCadence" to cadenceHz, "pedometerCadenceAvailable" to cadenceAvailable,
                "pedometerPace" to 0.0, "pedometerPaceAvailable" to false,
                "pedometerSessionStartMs" to sessionStartMs,
                "stepPeakTimes" to ArrayList(if (counterLiveMode) accelPeakTimes else detectorStepTimes),
                "accelPeakTimes" to ArrayList(accelPeakTimes),
                "stepEventSource" to latestStepEventSource,
                "stepAccelAmplitudeMps2" to lastStepAccelAmplitudeMps2,
                "stepCounterSteps" to observedCounterSteps, "stepCounterDelta" to observedCounterDelta,
                "counterLastEventAtMs" to lastStepCounterAtMs,
                "stepDetectorEvents" to stepDetectorEvents,
            ))
            payload.putAll(roninPayload())
            if (sessionFinalized && stepCounterReady) payload["authoritativeSteps"] = observedCounterSteps
        }
        activity.runOnUiThread { eventSink.success(payload) }
    }

    /**
     * RoNIN은 수평 속도를 내고 Android STEP_DETECTOR가 cadence를 낸다.
     * 둘의 시간축이 충분히 최근일 때만 speed/cadence를 한 걸음 거리 후보로
     * 공개한다. 이 값은 기존 confirmed 경로에는 들어가지 않는다.
     */
    private fun roninPayload(): Map<String, Any> {
        val payload = linkedMapOf<String, Any>(
            "roninSupported" to roninEstimator.supported,
            "roninModel" to RoninStrideEstimator.MODEL_NAME,
            "roninStatus" to roninEstimator.status,
        )
        val estimate = roninEstimator.latestEstimate
        val ageNs = estimate?.let {
            max(0L, SystemClock.elapsedRealtimeNanos() - it.inferredAtSensorNs)
        }
        val recent = ageNs != null && ageNs <= 2_000_000_000L
        val stride = if (
            recent &&
            estimate != null &&
            roninCadenceHz in 0.5..3.5
        ) {
            estimate.speedMps / roninCadenceHz
        } else {
            null
        }
        val usableStride = stride?.takeIf { it.isFinite() && it in 0.20..1.50 }
        payload["roninReady"] = recent && estimate != null
        if (estimate != null) {
            payload["roninSpeedMps"] = estimate.speedMps
            payload["roninSpeedStdMps"] = estimate.speedStdMps
            payload["roninEstimateAgeMs"] = (ageNs ?: 0L) / 1_000_000.0
        }
        if (roninCadenceHz > 0) {
            payload["roninCadenceHz"] = roninCadenceHz
        }
        if (usableStride != null) {
            payload["roninStrideMeters"] = usableStride
        }
        return payload
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        if (sensor.type == Sensor.TYPE_MAGNETIC_FIELD) {
            magneticAccuracy = when (accuracy) {
                SensorManager.SENSOR_STATUS_UNRELIABLE -> "uncalibrated"
                SensorManager.SENSOR_STATUS_ACCURACY_LOW -> "low"
                SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> "medium"
                SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> "high"
                else -> "unknown"
            }
        }
    }

    private fun sensorNsToEpochMs(sensorNs: Long): Double =
        System.currentTimeMillis().toDouble() - (SystemClock.elapsedRealtimeNanos() - sensorNs) / 1_000_000.0

    private fun copy3(from: FloatArray, to: FloatArray) {
        to[0] = from[0]; to[1] = from[1]; to[2] = from[2]
    }

    private fun magnitude(values: FloatArray): Double =
        sqrt(values.sumOf { value -> value.toDouble() * value.toDouble() })

    /** [a] − [b]를 (−180, 180]으로 접은 **부호 있는** 각차. 재앵커링의 방향이 이 부호다. */
    private fun shortestAngleDelta(a: Double, b: Double): Double =
        ((a - b + 540.0) % 360.0) - 180.0

    private fun angularDistance(a: Double, b: Double): Double =
        abs(shortestAngleDelta(a, b))

    private fun normalizeDegrees(degrees: Double): Double =
        ((degrees % 360.0) + 360.0) % 360.0
}
