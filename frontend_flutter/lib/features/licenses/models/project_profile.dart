class ProjectProfile {
  final String tagline;
  final String overview;
  final String audience;
  final String heroAsset;
  final String releaseDownloadUrl;
  final String image1Url;
  final String image2Url;
  final String image3Url;
  final List<String> platforms;
  final List<String> benefits;
  final List<String> requirements;
  final List<ProjectModuleInfo> modules;
  final List<String> installationSteps;
  final List<ProjectWorkflow> workflows;
  final List<ProjectMedia> gallery;

  const ProjectProfile({
    this.tagline = '',
    this.overview = '',
    this.audience = '',
    this.heroAsset = '',
    this.releaseDownloadUrl = '',
    this.image1Url = '',
    this.image2Url = '',
    this.image3Url = '',
    this.platforms = const [],
    this.benefits = const [],
    this.requirements = const [],
    this.modules = const [],
    this.installationSteps = const [],
    this.workflows = const [],
    this.gallery = const [],
  });

  bool get isEmpty =>
      tagline.isEmpty &&
      overview.isEmpty &&
      releaseDownloadUrl.isEmpty &&
      image1Url.isEmpty &&
      image2Url.isEmpty &&
      image3Url.isEmpty &&
      modules.isEmpty &&
      workflows.isEmpty;

  factory ProjectProfile.fromJson(dynamic value) {
    if (value is! Map) return const ProjectProfile();
    final json = Map<String, dynamic>.from(value);
    return ProjectProfile(
      tagline: _text(json['tagline']),
      overview: _text(json['overview']),
      audience: _text(json['audience']),
      heroAsset: _text(json['hero_asset']),
      releaseDownloadUrl: _text(json['release_download_url']),
      image1Url: _text(json['image_1_url']),
      image2Url: _text(json['image_2_url']),
      image3Url: _text(json['image_3_url']),
      platforms: _strings(json['platforms']),
      benefits: _strings(json['benefits']),
      requirements: _strings(json['requirements']),
      modules: _maps(json['modules']).map(ProjectModuleInfo.fromJson).toList(),
      installationSteps: _strings(json['installation_steps']),
      workflows: _maps(
        json['workflows'],
      ).map(ProjectWorkflow.fromJson).toList(),
      gallery: _maps(json['gallery']).map(ProjectMedia.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'tagline': tagline,
    'overview': overview,
    'audience': audience,
    'hero_asset': heroAsset,
    'release_download_url': releaseDownloadUrl,
    'image_1_url': image1Url,
    'image_2_url': image2Url,
    'image_3_url': image3Url,
    'platforms': platforms,
    'benefits': benefits,
    'requirements': requirements,
    'modules': modules.map((item) => item.toJson()).toList(),
    'installation_steps': installationSteps,
    'workflows': workflows.map((item) => item.toJson()).toList(),
    'gallery': gallery.map((item) => item.toJson()).toList(),
  };

  ProjectProfile copyWith({
    String? tagline,
    String? overview,
    String? audience,
    String? heroAsset,
    String? releaseDownloadUrl,
    String? image1Url,
    String? image2Url,
    String? image3Url,
    List<String>? platforms,
    List<String>? benefits,
    List<String>? requirements,
    List<ProjectModuleInfo>? modules,
    List<String>? installationSteps,
    List<ProjectWorkflow>? workflows,
    List<ProjectMedia>? gallery,
  }) {
    return ProjectProfile(
      tagline: tagline ?? this.tagline,
      overview: overview ?? this.overview,
      audience: audience ?? this.audience,
      heroAsset: heroAsset ?? this.heroAsset,
      releaseDownloadUrl: releaseDownloadUrl ?? this.releaseDownloadUrl,
      image1Url: image1Url ?? this.image1Url,
      image2Url: image2Url ?? this.image2Url,
      image3Url: image3Url ?? this.image3Url,
      platforms: platforms ?? this.platforms,
      benefits: benefits ?? this.benefits,
      requirements: requirements ?? this.requirements,
      modules: modules ?? this.modules,
      installationSteps: installationSteps ?? this.installationSteps,
      workflows: workflows ?? this.workflows,
      gallery: gallery ?? this.gallery,
    );
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static List<String> _strings(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(_text)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
}

class ProjectModuleInfo {
  final String title;
  final String description;
  final String icon;

  const ProjectModuleInfo({
    required this.title,
    required this.description,
    this.icon = '',
  });

  factory ProjectModuleInfo.fromJson(Map<String, dynamic> json) {
    return ProjectModuleInfo(
      title: json['title']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      icon: json['icon']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'icon': icon,
  };
}

class ProjectWorkflow {
  final String title;
  final String description;
  final List<String> steps;

  const ProjectWorkflow({
    required this.title,
    this.description = '',
    this.steps = const [],
  });

  factory ProjectWorkflow.fromJson(Map<String, dynamic> json) {
    return ProjectWorkflow(
      title: json['title']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      steps: ProjectProfile._strings(json['steps']),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'steps': steps,
  };
}

class ProjectMedia {
  final String title;
  final String asset;
  final String caption;

  const ProjectMedia({
    required this.title,
    required this.asset,
    this.caption = '',
  });

  factory ProjectMedia.fromJson(Map<String, dynamic> json) {
    return ProjectMedia(
      title: json['title']?.toString().trim() ?? '',
      asset: json['asset']?.toString().trim() ?? '',
      caption: json['caption']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'asset': asset,
    'caption': caption,
  };
}
