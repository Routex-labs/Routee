import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../models/place/outdoor_poi.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/map_overlay_guard.dart';
import '../../../../widgets/sheet_header.dart';
import '../../../../domain/geo/distance_format.dart';

/// 야외 장소 시트에서 사용자가 고른 다음 행동.
///
/// 예전에는 `transit`이 하나 더 있었다. 장소 상세는 "여기가 어디인가"를 보는
/// 자리라 이동 수단을 고르는 조작이 섞이면 안 되고, 수단은 길찾기에 들어간 뒤
/// 상단 줄에서 고른다.
enum OutdoorPoiAction { setOrigin, setDestination }

/// TMAP POI 검색 결과 한 건의 상세 시트.
///
/// 매장 시트([PlaceDetailSheet])와 나눠 둔 이유는 **가진 정보가 다르기**
/// 때문이다. 이쪽에는 층·노드·사진·메뉴가 없고 대신 주소·전화·직선 거리가
/// 있다. 한 시트에 합치면 절반이 늘 비어 있는 화면이 된다.
class OutdoorPoiSheet extends StatefulWidget {
  const OutdoorPoiSheet({
    super.key,
    required this.poi,
    required this.onCloseAll,
  });

  final OutdoorPoi poi;
  final VoidCallback onCloseAll;

  static Future<OutdoorPoiAction?> show(
    BuildContext context, {
    required OutdoorPoi poi,
    required VoidCallback onCloseAll,
  }) {
    return showModalBottomSheet<OutdoorPoiAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // 매장 시트와 같은 이유로 barrier를 깔지 않는다 — 시트가 열리며 지도가
      // 그 장소로 이동하는데, 확인하러 온 그 지점이 어두워지면 안 된다.
      barrierColor: Colors.transparent,
      builder: (context) => MapOverlayGuard(
        child: OutdoorPoiSheet(poi: poi, onCloseAll: onCloseAll),
      ),
    );
  }

  @override
  State<OutdoorPoiSheet> createState() => _OutdoorPoiSheetState();
}

class _OutdoorPoiSheetState extends State<OutdoorPoiSheet> {
  /// 뒤로/X로 닫았는지, barrier 탭으로 닫았는지 구분한다(매장 시트와 동일 규칙).
  bool _intentionalPop = false;

  void _markIntentional() => _intentionalPop = true;

  void _pop(OutdoorPoiAction action) {
    _markIntentional();
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final poi = widget.poi;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: DraggableScrollableSheet(
          initialChildSize: 0.42,
          minChildSize: 0.28,
          maxChildSize: 0.8,
          expand: false,
          builder: (context, scrollController) => GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: RoutexBottomSheet(
              // 표면은 Runtime Kit이, 드래그와 라우트는 앱이 갖는다. 여백은 조각마다
              // 달라서 본문이 소유한다.
              contentInset: RoutexBottomSheetContentInset.content,
              child: SingleChildScrollView(
                controller: scrollController,
                padding: EdgeInsets.only(
                  bottom: 20 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RoutexSheetHandle(),
                    SheetHeader(
                      onCloseAll: widget.onCloseAll,
                      onIntentionalPop: _markIntentional,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: _PoiCore(poi: poi),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _PoiActions(
                        onOrigin: () => _pop(OutdoorPoiAction.setOrigin),
                        onDestination: () =>
                            _pop(OutdoorPoiAction.setDestination),
                      ),
                    ),
                    if (poi.address != null || poi.telNo != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: _PoiFacts(poi: poi),
                      ),
                    // 이 데이터가 우리 건물 DB가 아니라 외부 지도에서 왔다는 사실을
                    // 밝힌다. 매장 상세와 정보의 깊이가 다른 이유가 여기 있고,
                    // 실제와 다를 때 사용자가 어디를 의심할지도 알 수 있다.
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Text(
                        '지도 데이터 제공: TMAP',
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PoiCore extends StatelessWidget {
  const _PoiCore({required this.poi});

  final OutdoorPoi poi;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (poi.category != null) poi.category!,
      if (poi.distanceMeters != null)
        '약 ${formatDistance(poi.distanceMeters!)}',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.blue50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.storefront_outlined,
            size: 24,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                poi.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              if (subtitleParts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitleParts.join(' · '),
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
              const SizedBox(height: 4),
              const Text(
                '건물 밖 장소',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 주소·전화처럼 "이 지점이 맞는지" 확인하는 데 쓰는 줄.
class _PoiFacts extends StatelessWidget {
  const _PoiFacts({required this.poi});

  final OutdoorPoi poi;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (poi.address != null)
          _FactRow(icon: Icons.place_outlined, text: poi.address!),
        if (poi.telNo != null) ...[
          const SizedBox(height: 10),
          _FactRow(icon: Icons.call_outlined, text: poi.telNo!),
        ],
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 17, color: AppColors.muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 13.5, color: AppColors.text),
        ),
      ),
    ],
  );
}

/// 출발·도착 한 줄. 매장 시트([PlaceDetailSheet])의 쌍과 자리·모양을 맞춘다 —
/// 두 시트에서 같은 조작이 다른 자리에 있으면 사용자는 매번 다시 찾는다.
class _PoiActions extends StatelessWidget {
  const _PoiActions({required this.onOrigin, required this.onDestination});

  final VoidCallback onOrigin;
  final VoidCallback onDestination;

  @override
  Widget build(BuildContext context) => RoutexPlaceActions(
    key: const ValueKey('outdoor-poi-actions'),
    onOrigin: onOrigin,
    onDestination: onDestination,
  );
}
