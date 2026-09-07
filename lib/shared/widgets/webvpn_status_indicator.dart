import 'package:flutter/material.dart';

import '../../data/models/client_backend.dart';
import '../theme/shuyo_theme.dart';

class WebVpnStatusIndicator extends StatelessWidget {
  const WebVpnStatusIndicator({
    super.key,
    required this.status,
  });

  final WebVpnServiceStatus status;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation(context);
    return Tooltip(
      message: presentation.label,
      child: Semantics(
        button: true,
        label: presentation.label,
        child: InkResponse(
          key: const ValueKey('webvpn-status-indicator'),
          radius: 20,
          onTap: () => _showDetails(context, presentation),
          child: SizedBox(
            width: 36,
            height: 48,
            child: Center(
              child: Container(
                key: const ValueKey('webvpn-status-dot'),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: presentation.color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _WebVpnStatusPresentation _presentation(BuildContext context) {
    final colors = context.shuyoColors;
    return switch (status.effectiveStateAt(DateTime.now())) {
      WebVpnServiceState.available => _WebVpnStatusPresentation(
          color: colors.brightness == Brightness.dark
              ? const Color(0xFF6AA9FF)
              : const Color(0xFF3478F6),
          label: 'WebVPN服务正常',
        ),
      WebVpnServiceState.degraded => _WebVpnStatusPresentation(
          color: colors.warning,
          label: 'WebVPN服务可能不稳定',
        ),
      WebVpnServiceState.unavailable => _WebVpnStatusPresentation(
          color: colors.danger,
          label: 'WebVPN服务暂不可用',
        ),
      WebVpnServiceState.unknown => _WebVpnStatusPresentation(
          color: colors.warning,
          label: '暂时无法获取WebVPN服务状态',
        ),
    };
  }

  Future<void> _showDetails(
    BuildContext context,
    _WebVpnStatusPresentation presentation,
  ) async {
    final checkedAt = status.checkedAt?.toLocal();
    final checkedText = checkedAt == null
        ? '尚未取得检查结果'
        : '${checkedAt.year}-${_twoDigits(checkedAt.month)}-'
            '${_twoDigits(checkedAt.day)} '
            '${_twoDigits(checkedAt.hour)}:${_twoDigits(checkedAt.minute)}';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('WebVPN服务状态'),
        content: Text(
          '${presentation.label}\n\n最近检查：$checkedText\n\n'
          '状态来自ShuYo服务器监测，仅供参考\n\n若服务不可用，可尝试使用校园网或学校 VPN',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _WebVpnStatusPresentation {
  const _WebVpnStatusPresentation({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;
}
