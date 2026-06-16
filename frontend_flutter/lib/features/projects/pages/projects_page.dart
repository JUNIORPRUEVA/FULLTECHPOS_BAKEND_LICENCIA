import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../../licenses/models/project.dart';
import '../../licenses/models/project_profile.dart';
import '../../licenses/services/projects_service.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  final ProjectsService _service = ProjectsService(
    sessionManager: SessionManager(),
  );

  List<Project> _projects = [];
  Project? _selected;
  bool _loading = true;
  String? _error;
  bool _editing = false;
  bool _saving = false;

  // Controladores de edición
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _codeCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _currencyCtrl;
  late TextEditingController _demoDaysCtrl;
  late TextEditingController _minMonthsCtrl;
  late TextEditingController _taglineCtrl;
  late TextEditingController _overviewCtrl;
  late TextEditingController _audienceCtrl;
  late TextEditingController _platformsCtrl;
  late TextEditingController _heroAssetCtrl;
  late TextEditingController _releaseUrlCtrl;
  late TextEditingController _image1UrlCtrl;
  late TextEditingController _image2UrlCtrl;
  late TextEditingController _image3UrlCtrl;
  late TextEditingController _benefitsCtrl;
  late TextEditingController _requirementsCtrl;
  late TextEditingController _modulesCtrl;
  late TextEditingController _installationCtrl;
  late TextEditingController _workflowsCtrl;
  late TextEditingController _galleryCtrl;
  bool _isPaid = true;
  bool _allowDemo = true;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _codeCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _priceCtrl = TextEditingController();
    _currencyCtrl = TextEditingController();
    _demoDaysCtrl = TextEditingController();
    _minMonthsCtrl = TextEditingController();
    _taglineCtrl = TextEditingController();
    _overviewCtrl = TextEditingController();
    _audienceCtrl = TextEditingController();
    _platformsCtrl = TextEditingController();
    _heroAssetCtrl = TextEditingController();
    _releaseUrlCtrl = TextEditingController();
    _image1UrlCtrl = TextEditingController();
    _image2UrlCtrl = TextEditingController();
    _image3UrlCtrl = TextEditingController();
    _benefitsCtrl = TextEditingController();
    _requirementsCtrl = TextEditingController();
    _modulesCtrl = TextEditingController();
    _installationCtrl = TextEditingController();
    _workflowsCtrl = TextEditingController();
    _galleryCtrl = TextEditingController();
    _loadProjects();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _currencyCtrl.dispose();
    _demoDaysCtrl.dispose();
    _minMonthsCtrl.dispose();
    _taglineCtrl.dispose();
    _overviewCtrl.dispose();
    _audienceCtrl.dispose();
    _platformsCtrl.dispose();
    _heroAssetCtrl.dispose();
    _releaseUrlCtrl.dispose();
    _image1UrlCtrl.dispose();
    _image2UrlCtrl.dispose();
    _image3UrlCtrl.dispose();
    _benefitsCtrl.dispose();
    _requirementsCtrl.dispose();
    _modulesCtrl.dispose();
    _installationCtrl.dispose();
    _workflowsCtrl.dispose();
    _galleryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = await _service.listProjects();
      // Ordenar proyectos por nombre alfabéticamente
      projects.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      setState(() {
        _projects = projects;
        _loading = false;
        // Re-seleccionar el mismo proyecto si estaba seleccionado
        if (_selected != null) {
          _selected = projects.cast<Project?>().firstWhere(
            (p) => p!.id == _selected!.id,
            orElse: () => null,
          );
        }
      });
    } on UnauthorizedException {
      setState(() => _loading = false);
      // No hacer nada mas: el callback global de AuthService ya limpio la sesion
      // y el router redirigira al login automaticamente.
      return;
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _selectProject(Project project) {
    setState(() {
      _selected = project;
      _editing = false;
    });
  }

  void _startEditing() {
    if (_selected == null) return;
    _nameCtrl.text = _selected!.name;
    _codeCtrl.text = _selected!.code;
    _descCtrl.text = _selected!.description ?? '';
    _priceCtrl.text = _selected!.monthlyPrice.toStringAsFixed(2);
    _currencyCtrl.text = _selected!.currency;
    _demoDaysCtrl.text = _selected!.demoDays.toString();
    _minMonthsCtrl.text = _selected!.minPurchaseMonths.toString();
    final profile = _selected!.profile;
    _taglineCtrl.text = profile.tagline;
    _overviewCtrl.text = profile.overview;
    _audienceCtrl.text = profile.audience;
    _platformsCtrl.text = profile.platforms.join(', ');
    _heroAssetCtrl.text = profile.heroAsset;
    _releaseUrlCtrl.text = profile.releaseDownloadUrl;
    _image1UrlCtrl.text = profile.image1Url;
    _image2UrlCtrl.text = profile.image2Url;
    _image3UrlCtrl.text = profile.image3Url;
    _benefitsCtrl.text = profile.benefits.join('\n');
    _requirementsCtrl.text = profile.requirements.join('\n');
    _modulesCtrl.text = profile.modules
        .map((item) => '${item.title} | ${item.description} | ${item.icon}')
        .join('\n');
    _installationCtrl.text = profile.installationSteps.join('\n');
    _workflowsCtrl.text = profile.workflows
        .map(
          (item) =>
              '${item.title} | ${item.description} | ${item.steps.join(' > ')}',
        )
        .join('\n');
    _galleryCtrl.text = profile.gallery
        .map((item) => '${item.title} | ${item.asset} | ${item.caption}')
        .join('\n');
    _isPaid = _selected!.isPaidProject;
    _allowDemo = _selected!.allowDemo;
    _isActive = _selected!.isActive;
    setState(() {
      _editing = true;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editing = false;
    });
  }

  Future<void> _saveProject() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selected == null) return;

    setState(() => _saving = true);

    try {
      final updated = await _service.updateProject(
        projectId: _selected!.id,
        name: _nameCtrl.text.trim(),
        code: _codeCtrl.text.trim().toUpperCase(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        monthlyPrice: double.tryParse(_priceCtrl.text) ?? 0,
        currency: _currencyCtrl.text.trim().toUpperCase(),
        demoDays: int.tryParse(_demoDaysCtrl.text) ?? 0,
        minPurchaseMonths: int.tryParse(_minMonthsCtrl.text) ?? 1,
        isPaidProject: _isPaid,
        allowDemo: _allowDemo,
        isActive: _isActive,
        profile: _buildProfileFromForm(),
      );

      setState(() {
        _selected = updated;
        _editing = false;
        _saving = false;
      });

      // Refrescar lista y mantener selección
      await _loadProjects();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Proyecto actualizado correctamente'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on UnauthorizedException {
      // No hacer nada: el callback global de AuthService ya limpio la sesion
      // y el router redirigira al login automaticamente.
      return;
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatCurrency(double amount, String currency) {
    final format = NumberFormat.currency(
      symbol: currency == 'USD' ? '\$' : currency,
      decimalDigits: 2,
    );
    return format.format(amount);
  }

  ProjectProfile _buildProfileFromForm() {
    return ProjectProfile(
      tagline: _taglineCtrl.text.trim(),
      overview: _overviewCtrl.text.trim(),
      audience: _audienceCtrl.text.trim(),
      heroAsset: _heroAssetCtrl.text.trim(),
      releaseDownloadUrl: _releaseUrlCtrl.text.trim(),
      image1Url: _image1UrlCtrl.text.trim(),
      image2Url: _image2UrlCtrl.text.trim(),
      image3Url: _image3UrlCtrl.text.trim(),
      platforms: _platformsCtrl.text
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      benefits: _lines(_benefitsCtrl.text),
      requirements: _lines(_requirementsCtrl.text),
      modules: _lines(_modulesCtrl.text).map((line) {
        final parts = line.split('|').map((item) => item.trim()).toList();
        return ProjectModuleInfo(
          title: parts.first,
          description: parts.length > 1 ? parts[1] : '',
          icon: parts.length > 2 ? parts[2] : '',
        );
      }).toList(),
      installationSteps: _lines(_installationCtrl.text),
      workflows: _lines(_workflowsCtrl.text).map((line) {
        final parts = line.split('|').map((item) => item.trim()).toList();
        return ProjectWorkflow(
          title: parts.first,
          description: parts.length > 1 ? parts[1] : '',
          steps: parts.length > 2
              ? parts[2]
                    .split('>')
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList()
              : const [],
        );
      }).toList(),
      gallery: _lines(_galleryCtrl.text).map((line) {
        final parts = line.split('|').map((item) => item.trim()).toList();
        return ProjectMedia(
          title: parts.first,
          asset: parts.length > 1 ? parts[1] : '',
          caption: parts.length > 2 ? parts[2] : '',
        );
      }).toList(),
    );
  }

  List<String> _lines(String value) => value
      .split('\n')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Lista de proyectos
        Expanded(child: _buildProjectList()),
        // Panel de detalle/edición
        if (_selected != null)
          Container(
            width: AppSpacing.detailPanelWidth,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(left: BorderSide(color: AppColors.border)),
            ),
            child: _editing ? _buildEditPanel() : _buildDetailPanel(),
          ),
      ],
    );
  }

  Widget _buildProjectList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadProjects,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_projects.isEmpty) {
      return const Center(
        child: Text(
          'No hay proyectos',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header con título
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Text(
                'Proyectos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${_projects.length} proyectos',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        // Lista
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.sm),
            itemCount: _projects.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (_, index) {
              final project = _projects[index];
              final isSelected = _selected?.id == project.id;
              return _ProjectListTile(
                project: project,
                selected: isSelected,
                onTap: () => _selectProject(project),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDetailPanel() {
    final p = _selected!;
    return Column(
      children: [
        // Header
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Detalle del proyecto',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _selected = null),
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
        // Contenido
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              // Botón editar
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _startEditing,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar proyecto'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (!p.profile.isEmpty) ...[
                _buildProductHero(p),
                const SizedBox(height: AppSpacing.md),
                _profileSection(
                  title: 'Acerca del producto',
                  icon: Icons.info_outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.profile.overview,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (p.profile.audience.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _labeledText('Ideal para', p.profile.audience),
                      ],
                    ],
                  ),
                ),
                _profileSection(
                  title: 'Descarga e imágenes',
                  icon: Icons.download_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _downloadField(
                        'Enlace release / descarga',
                        p.profile.releaseDownloadUrl,
                      ),
                      const SizedBox(height: 10),
                      _imageLinkCard(
                        title: 'Imagen 1',
                        source: p.profile.image1Url,
                        placeholder:
                            'Pendiente: pega aquí la imagen principal del proyecto.',
                      ),
                      _imageLinkCard(
                        title: 'Imagen 2',
                        source: p.profile.image2Url,
                        placeholder:
                            'Pendiente: pega aquí una imagen del proceso principal.',
                      ),
                      _imageLinkCard(
                        title: 'Imagen 3',
                        source: p.profile.image3Url,
                        placeholder:
                            'Pendiente: pega aquí una imagen de reportes, caja o resultados.',
                      ),
                    ],
                  ),
                ),
                _profileSection(
                  title: 'Beneficios principales',
                  icon: Icons.verified_outlined,
                  child: _bulletList(p.profile.benefits),
                ),
                _profileSection(
                  title: 'Módulos y funcionalidades',
                  icon: Icons.grid_view_rounded,
                  child: Column(
                    children: p.profile.modules
                        .map((item) => _moduleCard(item))
                        .toList(),
                  ),
                ),
                _profileSection(
                  title: 'Instalación paso a paso',
                  icon: Icons.install_desktop_outlined,
                  child: _numberedList(p.profile.installationSteps),
                ),
                _profileSection(
                  title: 'Procedimientos de trabajo',
                  icon: Icons.account_tree_outlined,
                  child: Column(
                    children: p.profile.workflows
                        .map((workflow) => _workflowCard(workflow))
                        .toList(),
                  ),
                ),
                _profileSection(
                  title: 'Requisitos',
                  icon: Icons.fact_check_outlined,
                  child: _bulletList(p.profile.requirements),
                ),
                if (p.profile.gallery.isNotEmpty)
                  _profileSection(
                    title: 'Galería',
                    icon: Icons.photo_library_outlined,
                    child: Column(
                      children: p.profile.gallery
                          .map((media) => _mediaCard(media))
                          .toList(),
                    ),
                  ),
              ] else
                _emptyProfileCard(),
              _profileSection(
                title: 'Configuración del proyecto',
                icon: Icons.settings_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailField('ID', p.id),
                    _detailField('Nombre', p.name),
                    _detailField('Código', p.code),
                    _detailField('Descripción', p.description ?? '—'),
                    _detailField(
                      'Precio mensual',
                      '${_formatCurrency(p.monthlyPrice, p.currency)} / mes',
                    ),
                    _detailField('Moneda', p.currency),
                    _detailField('Días demo', '${p.demoDays} días'),
                    _detailField(
                      'Meses mínimos',
                      '${p.minPurchaseMonths} meses',
                    ),
                    _detailField(
                      'Requiere pago',
                      p.isPaidProject ? 'Sí' : 'No',
                    ),
                    _detailField('Permite demo', p.allowDemo ? 'Sí' : 'No'),
                    _detailField('Estado', p.isActive ? 'Activo' : 'Inactivo'),
                    if (p.createdAt != null)
                      _detailField(
                        'Creado',
                        DateFormat('dd/MM/yyyy HH:mm').format(p.createdAt!),
                      ),
                    if (p.updatedAt != null)
                      _detailField(
                        'Actualizado',
                        DateFormat('dd/MM/yyyy HH:mm').format(p.updatedAt!),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildProductHero(Project project) {
    final profile = project.profile;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1A56DB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _projectImage(profile.heroAsset, size: 82),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (profile.tagline.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    profile.tagline,
                    style: const TextStyle(
                      color: Color(0xFFDCE8FF),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                if (profile.platforms.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: profile.platforms
                        .map(
                          (platform) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              platform,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _labeledText(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.groups_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletList(List<String> items) {
    if (items.isEmpty) return const Text('Sin información registrada.');
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _numberedList(List<String> items) {
    return Column(
      children: [
        for (var index = 0; index < items.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    items[index],
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _moduleCard(ProjectModuleInfo item) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              _moduleIcon(item.icon),
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _workflowCard(ProjectWorkflow workflow) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            workflow.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (workflow.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              workflow.description,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _numberedList(workflow.steps),
        ],
      ),
    );
  }

  Widget _downloadField(String label, String value) {
    final displayValue = value.isEmpty ? 'Pendiente de completar' : value;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            displayValue,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: value.isEmpty ? AppColors.textMuted : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageLinkCard({
    required String title,
    required String source,
    required String placeholder,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 145,
            width: double.infinity,
            child: _projectImage(source, fit: BoxFit.contain),
          ),
          const SizedBox(height: 8),
          SelectableText(
            source.isEmpty ? placeholder : source,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: source.isEmpty ? AppColors.textMuted : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mediaCard(ProjectMedia media) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 190,
            width: double.infinity,
            child: _projectImage(media.asset, fit: BoxFit.contain),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (media.caption.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    media.caption,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _projectImage(
    String source, {
    double? size,
    BoxFit fit = BoxFit.cover,
  }) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: AppColors.primaryLight,
      child: const Icon(Icons.apps_rounded, size: 36, color: AppColors.primary),
    );
    if (source.isEmpty) return fallback;
    final image = source.startsWith('http://') || source.startsWith('https://')
        ? Image.network(
            source,
            width: size,
            height: size,
            fit: fit,
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.asset(
            source,
            width: size,
            height: size,
            fit: fit,
            errorBuilder: (_, _, _) => fallback,
          );
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: image);
  }

  Widget _emptyProfileCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: const Text(
        'Este proyecto todavía no tiene documentación de producto. '
        'Usa Editar proyecto para completar sus módulos y procedimientos.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
    );
  }

  IconData _moduleIcon(String key) {
    const icons = <String, IconData>{
      'dashboard': Icons.dashboard_outlined,
      'clients': Icons.groups_outlined,
      'loans': Icons.account_balance_wallet_outlined,
      'calculator': Icons.calculate_outlined,
      'payments': Icons.payments_outlined,
      'contracts': Icons.description_outlined,
      'cash': Icons.point_of_sale_outlined,
      'reports': Icons.insert_chart_outlined,
      'print': Icons.print_outlined,
      'license': Icons.workspace_premium_outlined,
      'sales': Icons.shopping_cart_checkout_outlined,
      'inventory': Icons.inventory_2_outlined,
      'quotes': Icons.request_quote_outlined,
      'purchases': Icons.local_shipping_outlined,
      'returns': Icons.assignment_return_outlined,
      'users': Icons.manage_accounts_outlined,
      'electronic_invoice': Icons.receipt_long_outlined,
      'backup': Icons.cloud_sync_outlined,
    };
    return icons[key] ?? Icons.widgets_outlined;
  }

  Widget _buildEditPanel() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Header
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Editar proyecto',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _cancelEditing,
                  tooltip: 'Cancelar',
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          // Formulario
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _buildTextField(
                  controller: _nameCtrl,
                  label: 'Nombre',
                  required: true,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _codeCtrl,
                  label: 'Código',
                  required: true,
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    return null;
                  },
                  onChanged: (v) {
                    _codeCtrl.value = TextEditingValue(
                      text: v.toUpperCase(),
                      selection: TextSelection.collapsed(offset: v.length),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _descCtrl,
                  label: 'Descripción',
                  maxLines: 3,
                ),
                const SizedBox(height: AppSpacing.lg),
                _editSectionTitle(
                  'Información del producto',
                  'Contenido que se mostrará en la ficha de APYRA.',
                ),
                _buildTextField(
                  controller: _taglineCtrl,
                  label: 'Frase principal',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _overviewCtrl,
                  label: 'Descripción completa',
                  maxLines: 6,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _audienceCtrl,
                  label: 'Público objetivo',
                  maxLines: 3,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _platformsCtrl,
                  label: 'Plataformas',
                  hintText: 'Windows, Android',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _heroAssetCtrl,
                  label: 'Imagen principal',
                  hintText: 'assets/projects/imagen.png o https://...',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _releaseUrlCtrl,
                  label: 'Enlace release / descarga',
                  hintText: 'https://github.com/.../releases/download/...',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _image1UrlCtrl,
                  label: 'Imagen 1 URL',
                  hintText: 'https://... o assets/projects/imagen1.png',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _image2UrlCtrl,
                  label: 'Imagen 2 URL',
                  hintText: 'https://... o assets/projects/imagen2.png',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _image3UrlCtrl,
                  label: 'Imagen 3 URL',
                  hintText: 'https://... o assets/projects/imagen3.png',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _benefitsCtrl,
                  label: 'Beneficios',
                  hintText: 'Uno por línea',
                  maxLines: 6,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _requirementsCtrl,
                  label: 'Requisitos',
                  hintText: 'Uno por línea',
                  maxLines: 6,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _modulesCtrl,
                  label: 'Módulos y funcionalidades',
                  hintText: 'Título | Descripción | icono',
                  maxLines: 10,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _installationCtrl,
                  label: 'Pasos de instalación',
                  hintText: 'Un paso por línea',
                  maxLines: 8,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _workflowsCtrl,
                  label: 'Procedimientos',
                  hintText: 'Título | Descripción | Paso 1 > Paso 2 > Paso 3',
                  maxLines: 12,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _galleryCtrl,
                  label: 'Galería',
                  hintText:
                      'Título | URL de imagen (puede quedar vacía) | descripción',
                  maxLines: 5,
                ),
                const SizedBox(height: AppSpacing.lg),
                _editSectionTitle(
                  'Licencia y facturación',
                  'Configuración comercial existente del proyecto.',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _priceCtrl,
                  label: 'Precio mensual',
                  keyboardType: TextInputType.number,
                  required: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    final price = double.tryParse(v);
                    if (price == null || price < 0) return 'Debe ser >= 0';
                    if (_isPaid && price <= 0) {
                      return 'Debe ser > 0 si requiere pago';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _currencyCtrl,
                  label: 'Moneda',
                  required: true,
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _demoDaysCtrl,
                  label: 'Días demo',
                  keyboardType: TextInputType.number,
                  required: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    final days = int.tryParse(v);
                    if (days == null || days < 0) return 'Debe ser >= 0';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _minMonthsCtrl,
                  label: 'Meses mínimos',
                  keyboardType: TextInputType.number,
                  required: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    final months = int.tryParse(v);
                    if (months == null || months < 1) return 'Debe ser >= 1';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                // Switches
                _buildSwitch('Requiere pago', _isPaid, (v) {
                  setState(() => _isPaid = v);
                  // Re-validar precio si cambia
                  _formKey.currentState?.validate();
                }),
                const SizedBox(height: AppSpacing.sm),
                _buildSwitch('Permite demo', _allowDemo, (v) {
                  setState(() => _allowDemo = v);
                }),
                const SizedBox(height: AppSpacing.sm),
                _buildSwitch('Activo', _isActive, (v) {
                  setState(() => _isActive = v);
                }),
                const SizedBox(height: AppSpacing.lg),
                // Botones
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _cancelEditing,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _saving ? null : _saveProject,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Guardar cambios'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hintText,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hintText,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }

  Widget _editSectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _ProjectListTile extends StatelessWidget {
  final Project project;
  final bool selected;
  final VoidCallback onTap;

  const _ProjectListTile({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nombre y código
            Row(
              children: [
                Expanded(
                  child: Text(
                    project.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                StatusBadge(
                  label: project.isActive ? 'Activo' : 'Inactivo',
                  type: project.isActive
                      ? StatusType.active
                      : StatusType.inactive,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Código: ${project.code}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            // Precio
            Row(
              children: [
                const Icon(
                  Icons.attach_money,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${project.currency} ${project.monthlyPrice.toStringAsFixed(2)} / mes',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Demo y mínimo
            Row(
              children: [
                const Icon(
                  Icons.free_breakfast_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Demo: ${project.demoDays} días',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.calendar_month_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Mín: ${project.minPurchaseMonths} meses',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Pago
            Row(
              children: [
                Icon(
                  project.isPaidProject
                      ? Icons.lock_outline
                      : Icons.lock_open_outlined,
                  size: 14,
                  color: project.isPaidProject
                      ? AppColors.warning
                      : AppColors.success,
                ),
                const SizedBox(width: 4),
                Text(
                  project.isPaidProject ? 'Pago: Sí' : 'Pago: No',
                  style: TextStyle(
                    fontSize: 12,
                    color: project.isPaidProject
                        ? AppColors.warning
                        : AppColors.success,
                  ),
                ),
                if (project.allowDemo) ...[
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.science_outlined,
                    size: 14,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Demo disponible',
                    style: TextStyle(fontSize: 12, color: AppColors.info),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
