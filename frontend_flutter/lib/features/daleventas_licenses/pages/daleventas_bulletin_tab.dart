import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';

/// Publicación del boletín del proyecto.
///
/// Es información **local del dispositivo** (se guarda en preferencias): no
/// modifica datos de negocio ni publica nada en el backend.
class DaleVentasBulletinPost {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;

  const DaleVentasBulletinPost({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'message': message,
    'createdAt': createdAt.toIso8601String(),
  };

  static DaleVentasBulletinPost? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final map = value.cast<dynamic, dynamic>();
    final title = map['title']?.toString().trim() ?? '';
    final message = map['message']?.toString().trim() ?? '';
    if (title.isEmpty && message.isEmpty) return null;
    final createdAt =
        DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now();
    return DaleVentasBulletinPost(
      id: map['id']?.toString() ?? createdAt.microsecondsSinceEpoch.toString(),
      title: title,
      message: message,
      createdAt: createdAt,
    );
  }
}

/// Pestaña "Boletín" de la consola del proyecto DaleVentas.
///
/// Permite dejar avisos y novedades del proyecto (mantenimiento, cambios de
/// precio, notas de soporte). Se guarda en el dispositivo y se ordena del más
/// reciente al más antiguo.
class DaleVentasBulletinTab extends StatefulWidget {
  /// Clave de almacenamiento (inyectable en tests).
  final String storageKey;

  const DaleVentasBulletinTab({
    super.key,
    this.storageKey = 'daleventas_bulletin_v1',
  });

  @override
  State<DaleVentasBulletinTab> createState() => _DaleVentasBulletinTabState();
}

class _DaleVentasBulletinTabState extends State<DaleVentasBulletinTab> {
  static const List<String> _quickTitles = <String>[
    'Novedad',
    'Mantenimiento',
    'Cambio de precio',
    'Soporte',
  ];

  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<DaleVentasBulletinPost> _posts = const [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPosts() async {
    final prefs = await _prefs();
    final raw = prefs?.getString(widget.storageKey);
    final posts = <DaleVentasBulletinPost>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final post = DaleVentasBulletinPost.tryFromJson(item);
            if (post != null) posts.add(post);
          }
        }
      } catch (_) {
        // Datos corruptos: se ignoran y el boletín queda vacío.
      }
    }
    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.setString(
      widget.storageKey,
      jsonEncode(_posts.map((post) => post.toJson()).toList()),
    );
  }

  Future<void> _publish() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final title = _titleCtrl.text.trim();
    final message = _messageCtrl.text.trim();

    setState(() => _saving = true);
    final post = DaleVentasBulletinPost(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.isEmpty ? 'Novedad' : title,
      message: message,
      createdAt: DateTime.now(),
    );
    setState(() {
      _posts = <DaleVentasBulletinPost>[post, ..._posts];
      _saving = false;
    });
    _titleCtrl.clear();
    _messageCtrl.clear();
    await _persist();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Publicado en el boletín'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _delete(DaleVentasBulletinPost post) async {
    setState(() {
      _posts = _posts.where((item) => item.id != post.id).toList();
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _buildIntro(),
        const SizedBox(height: 14),
        _buildComposer(),
        const SizedBox(height: 14),
        _buildHeader(),
        const SizedBox(height: 10),
        if (_posts.isEmpty)
          const EmptyState(
            icon: Icons.campaign_outlined,
            title: 'El boletín está vacío',
            subtitle:
                'Escribe el primer aviso del proyecto: novedades, '
                'mantenimientos o notas de soporte para DaleVentas POS.',
          )
        else
          for (final post in _posts) ...[
            _BulletinCard(post: post, onDelete: () => _delete(post)),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x331A56DB),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Boletín del proyecto',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Avisos y novedades',
                      style: TextStyle(fontSize: 11.5, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Deja aquí los avisos importantes del proyecto para tenerlos a mano '
            'en el móvil.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nueva publicación',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final title in _quickTitles)
                  _QuickChip(
                    label: title,
                    onTap: () => setState(() {
                      _titleCtrl.text = title;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(hintText: 'Título del aviso'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _messageCtrl,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'Escribe el detalle del aviso...',
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Escribe el contenido del aviso'
                  : null,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _publish,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Publicar en el boletín'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text(
          'Publicaciones',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        Text(
          _posts.length == 1 ? '1 aviso' : '${_posts.length} avisos',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _BulletinCard extends StatelessWidget {
  final DaleVentasBulletinPost post;
  final VoidCallback onDelete;

  const _BulletinCard({required this.post, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.push_pin_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Appyra · '
                      '${DateFormat('dd/MM/yyyy HH:mm').format(post.createdAt.toLocal())}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Eliminar publicación',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            post.message,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
