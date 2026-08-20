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
import com.google.android.gms.location.DeviceOrientation
import com.google.android.gms.location.DeviceOrientationListener
import com.google.android.gms.location.DeviceOrientationRequest
import com.google.android.gms.location.FusedOrientationProviderClient
import com.google.android.gms.location.LocationServices
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

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
    private val fopClient: FusedOrientationProviderClient =
        LocationServices.getFusedOrientationProviderClient(activity)
    private val fopListener = DeviceOrientationListener { orientation ->
        updateFusedOrientation(orientation)
    }
    private var sink: EventChannel.EventSink? = null

    private val rotationMatrix = FloatArray(9)
    private val fopMatrix = FloatArray(9)
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
    private var rvHeadingDeg = 0.0
    private var fopHeadingDeg = -1.0
    private var fopHeadingErrorDeg = -1.0
    private var fopBlendHeadingDeg = -1.0
    private var fopAtNs = 0L
    private var fopSupported = false
    private var fopStatus = "unavailable"
    private var fusedHeadingDeg = 0.0
    private var gyroHeadingDeg = 0.0
    private var gyroHeadingInitialized = false
    private var headingHoldActive = false
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
    private var lastRotationNs = 0L
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
        stopFusedOrientation()
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

    /**
     * FusedOrientationProvider 구독. heading에만 쓴다.
     *
     * RoNIN 입력과 월드 가속 변환은 계속 플랫폼 rotation vector를 쓴다 —
     * 자세 소스를 통째로 바꾸면 보폭 추론까지 한 번에 흔들려서, 결과가
     * 나빠졌을 때 heading 때문인지 보폭 때문인지 가릴 수 없다.
     */
    private fun startFusedOrientation() {
        val request = DeviceOrientationRequest.Builder(
            DeviceOrientationRequest.OUTPUT_PERIOD_DEFAULT,
        ).build()
        fopStatus = "requested"
        runCatching {
            fopClient.requestOrientationUpdates(
                request,
                ContextCompat.getMainExecutor(activity),
                fopListener,
            )
        }.onFailure { error ->
            fopSupported = false
            fopStatus = "request_failed:${error.javaClass.simpleName}"
        }
    }

    private fun stopFusedOrientation() {
        runCatching { fopClient.removeOrientationUpdates(fopListener) }
        fopAtNs = 0L
        fopStatus = "stopped"
    }

    /**
     * FOP 자세를 우리 forward 축 규약으로 다시 계산한다.
     *
     * `getHeadingDegrees()`를 그대로 쓰지 않는 이유는 그 값의 forward 축 정의가
     * 우리 +Y/-Z 블렌드와 같다는 보장이 없어서다. 같은 ENU 자세에서 같은 식을
     * 돌리면 소스만 갈리고 규약은 유지된다. 원본 heading은 진단으로 함께 싣는다.
     */
    private fun updateFusedOrientation(orientationSample: DeviceOrientation) {
        val attitude = orientationSample.attitude
        if (attitude.size < 4) return
        SensorManager.getRotationMatrixFromVector(fopMatrix, attitude)
        fopBlendHeadingDeg = forwardHeadingFromMatrix(fopMatrix) ?: return
        fopHeadingDeg = orientationSample.headingDegrees.toDouble()
        fopHeadingErrorDeg = orientationSample.headingErrorDegrees.toDouble()
        fopAtNs = SystemClock.elapsedRealtimeNanos()
        fopSupported = true
        fopStatus = "streaming"
    }

    /** FOP 표본이 아직 유효한지. 끊기면 플랫폼 rotation vector로 되돌아간다. */
    private fun fopFresh(): Boolean =
        fopAtNs != 0L &&
            SystemClock.elapsedRealtimeNanos() - fopAtNs <= FOP_STALE_NS

    /**
     * device→world 행렬에서 진행 정면 방위를 뽑는다. 수평 성분이 너무 짧으면
     * 방위가 의미 없으므로 null이다(기존 0.4 문턱과 같은 값).
     */
    private fun forwardHeadingFromMatrix(m: FloatArray): Double? {
        // +Y(top) is the usual forward axis. When upright, smoothly use the
        // rear-camera (-Z) direction so portrait and held-flat walks agree.
        val topUp = m[7].toDouble()
        val cameraWeight = ((topUp - 0.5) / 0.37).coerceIn(0.0, 1.0)
        val forwardEast = m[1].toDouble() - cameraWeight * m[2]
        val forwardNorth = m[4].toDouble() - cameraWeight * m[5]
        if (sqrt(forwardEast * forwardEast + forwardNorth * forwardNorth) <= 0.4) return null
        return normalizeDegrees(Math.toDegrees(atan2(forwardEast, forwardNorth)))
    }

    private fun startSensors() {
        sensorManager.unregisterListener(this)
        startFusedOrientation()
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
        val vendorAccuracyDeg = event.values.getOrNull(4)?.toDouble()?.takeIf { it >= 0 }
            ?.let { Math.toDegrees(it) } ?: -1.0

        val rvHeading = forwardHeadingFromMatrix(rotationMatrix)
        if (rvHeading != null) {
            rvHeadingDeg = rvHeading
            // 플랫폼 rotation vector 값은 진단으로 그대로 남긴다. FOP를 쓰는
            // 동안에도 이 값이 있어야 둘을 나란히 놓고 어느 쪽이 틀렸는지 판정한다.
            deviceHeadingDeg = rvHeading
        }
        // SM-G996N은 values[4]를 -1로 준다. FOP의 headingError가 이 기기에서
        // 유일한 정량 불확실성이라, 있으면 그쪽을 쓴다.
        val useFop = fopFresh()
        rotationHeadingAccuracyDeg = if (useFop && fopHeadingErrorDeg >= 0) {
            fopHeadingErrorDeg
        } else {
            vendorAccuracyDeg
        }
        val forward = if (useFop) fopBlendHeadingDeg else rvHeading
        if (forward != null && forward >= 0) {
            rawRotationHeadingDeg = forward
            if (!gyroHeadingInitialized) {
                gyroHeadingDeg = rawRotationHeadingDeg
                gyroHeadingInitialized = true
            } else {
                pullGyroHeadingTowardRotation(event.timestamp)
            }
        }
        lastRotationNs = event.timestamp
        yawDeg = normalizeDegrees(Math.toDegrees(orientation[0].toDouble()))
        pitchDeg = Math.toDegrees(orientation[1].toDouble())
        rollDeg = Math.toDegrees(orientation[2].toDouble())
    }

    /**
     * 적분 heading을 rotation vector 쪽으로 상시 끌어당긴다.
     *
     * seed를 세션당 한 번만 하면 자이로 바이어스가 단조 누적되고, 그 편차가
     * 곧 hold 진입 조건(innovation)이라 스스로를 가둔다 — 초기 오차가 세션
     * 내내 박제되던 원인이다. 상시로 당기면 정상 구간에서 편차가 0 근처에
     * 머물러 래치가 성립하지 않고, hold 중에도 느리게나마 좁혀지므로 탈출이
     * 보장된다. hold 중 시정수를 크게 두는 것은 진짜 자기 교란을 몇 초간
     * 버티기 위한 값이며, 그 대가로 교란이 길어지면 오차를 따라간다. 무한히
     * 벌어지는 것보다 유계인 쪽이 낫다는 판단이다.
     */
    private fun pullGyroHeadingTowardRotation(sensorNs: Long) {
        if (lastRotationNs == 0L) return
        val dt = (sensorNs - lastRotationNs) / 1_000_000_000.0
        if (dt <= 0.0 || dt > 0.5) return
        val tau = if (headingHoldActive) HOLD_PULL_TAU_S else TRACK_PULL_TAU_S
        val gain = (dt / tau).coerceIn(0.0, 1.0)
        val delta = signedDelta(rawRotationHeadingDeg, gyroHeadingDeg)
        gyroHeadingDeg = normalizeDegrees(gyroHeadingDeg + gain * delta)
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
     * values relock immediately. SensorManager still supplies the base fusion. */
    private fun selectHeading() {
        // hold 중에도 갱신한다. early return 뒤에 두면 자기 교란으로 hold에
        // 들어간 순간 baseline이 얼어붙어 fieldDeviation이 영원히 임계 위에
        // 남는다 — 진입 조건이 스스로를 유지시키는 두 번째 래치였다.
        if (magneticField > 1) {
            magneticFieldBaseline = (magneticFieldBaseline ?: magneticField) * 0.985 + magneticField * 0.015
        }
        val baseline = magneticFieldBaseline
        val fieldDeviation = if (baseline != null && baseline > 1 && magneticField > 1) {
            abs(magneticField - baseline) / baseline
        } else 0.0
        val innovation = angularDistance(rawRotationHeadingDeg, gyroHeadingDeg)
        val usingFop = fopFresh()
        // FOP를 쓰는 동안에는 원시 자력계 정확도 플래그로 hold하지 않는다.
        // 실측에서 이 플래그가 세션 내내 "low"라 hold가 상시 켜졌는데, 그
        // 보정을 대신 해 주는 게 바로 FOP다. 대신 FOP가 주는 headingError를
        // 문턱으로 쓴다 — 벤더가 -1로 주던 값을 처음으로 숫자로 받는다.
        val poorMagnetic = !usingFop &&
            (magneticAccuracy == "low" || magneticAccuracy == "uncalibrated")
        val inaccurate = rotationHeadingAccuracyDeg > 35
        val activeSource = if (usingFop) "fused_orientation_provider" else rotationSource
        val useGyroHold = activeSource.contains("game_rotation_vector") || poorMagnetic ||
            fieldDeviation > 0.35 || innovation > 35 || inaccurate
        headingHoldActive = useGyroHold
        if (useGyroHold && gyroHeadingInitialized) {
            fusedHeadingDeg = gyroHeadingDeg
            // TYPE_ROTATION_VECTOR는 자력계까지 포함한 9-axis fusion이라
            // gyro hold 중에도 마지막 절대 북 기준 frame을 이어받는다. hold는
            // "정확도가 낮다"는 뜻이지, heading frame 자체가 arbitrary로
            // 바뀐다는 뜻은 아니다. 반대로 game rotation vector는 처음부터
            // 자력계를 쓰지 않으므로 기존처럼 absolute heading으로 선언하지
            // 않는다.
            selectedHeadingSource = if (usingFop) {
                "fused_orientation_provider+gyro_hold"
            } else if (rotationSource.contains("rotation_vector") &&
                !rotationSource.contains("game")
            ) {
                "sensor_manager/rotation_vector+gyro_hold"
            } else {
                "sensor_manager/gyro_hold"
            }
            headingStable = false
            return
        }
        fusedHeadingDeg = rawRotationHeadingDeg
        selectedHeadingSource = activeSource
        headingStable = usingFop ||
            (rotationSource.contains("rotation_vector") && !rotationSource.contains("game"))
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
        headingHoldActive = false
        lastRotationNs = 0L
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
                // FOP 원본 heading과 그 불확실성. 우리가 재계산한 블렌드 값과
                // 나란히 남겨야 "FOP가 틀렸나, 우리 축 규약이 틀렸나"를 가른다.
                "fopSupported" to fopSupported, "fopStatus" to fopStatus,
                "fopHeadingDeg" to fopHeadingDeg,
                "fopHeadingErrorDeg" to fopHeadingErrorDeg,
                "fopBlendHeadingDeg" to fopBlendHeadingDeg,
                "rvHeadingDeg" to rvHeadingDeg,
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

    private fun angularDistance(a: Double, b: Double): Double =
        abs(((a - b + 540.0) % 360.0) - 180.0)

    /** [current]에서 [target]까지의 최단 회전(-180..180). 360° 경계에서도 부호가 맞는다. */
    private fun signedDelta(target: Double, current: Double): Double =
        ((target - current + 540.0) % 360.0) - 180.0

    private fun normalizeDegrees(degrees: Double): Double =
        ((degrees % 360.0) + 360.0) % 360.0

    private companion object {
        // 정상 구간: RV를 사실상 따라간다. 편차가 못 쌓이므로 래치가 불가능하다.
        const val TRACK_PULL_TAU_S = 0.5
        // hold 구간: 몇 초짜리 자기 교란은 버티고, 길어지면 유계로 수렴한다.
        const val HOLD_PULL_TAU_S = 20.0
        // FOP 표본이 이보다 오래되면 플랫폼 rotation vector로 되돌아간다.
        // Play Services 미설치·업데이트 중에도 heading이 끊기지 않아야 한다.
        const val FOP_STALE_NS = 1_000_000_000L
    }
}
