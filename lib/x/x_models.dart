import 'package:meta/meta.dart';

enum XContentSource { account, home, search }

enum XContentMood { any, funny, calm, weird, scary, mad, uplifting }

enum XContentTopic { any, science, engineering, music, memes, art, technology }

enum XContentColor { any, blue, orange, purple, red, green }

@immutable
final class XFollow {
  const XFollow({
    required this.id,
    required this.name,
    required this.username,
    required this.description,
    required this.avatarUrl,
    required this.syncedAt,
    required this.isFollowing,
    required this.followsYou,
  });

  final String id;
  final String name;
  final String username;
  final String description;
  final Uri? avatarUrl;
  final DateTime syncedAt;
  final bool isFollowing;
  final bool followsYou;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'username': username,
    'description': description,
    'avatarUrl': avatarUrl?.toString(),
    'syncedAt': syncedAt.toUtc().toIso8601String(),
    'isFollowing': isFollowing,
    'followsYou': followsYou,
  };

  static XFollow fromJson(Map<String, Object?> json) => XFollow(
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    username: (json['username'] as String?) ?? '',
    description: (json['description'] as String?) ?? '',
    avatarUrl: Uri.tryParse((json['avatarUrl'] as String?) ?? ''),
    syncedAt:
        DateTime.tryParse((json['syncedAt'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    isFollowing: (json['isFollowing'] as bool?) ?? true,
    followsYou: (json['followsYou'] as bool?) ?? false,
  );

  XFollow copyWith({bool? isFollowing, bool? followsYou}) => XFollow(
    id: id,
    name: name,
    username: username,
    description: description,
    avatarUrl: avatarUrl,
    syncedAt: syncedAt,
    isFollowing: isFollowing ?? this.isFollowing,
    followsYou: followsYou ?? this.followsYou,
  );
}

@immutable
final class XContentScore {
  const XContentScore({
    required this.postId,
    required this.mood,
    required this.topics,
    required this.colors,
    required this.weirdness,
    required this.negativity,
    required this.meme,
    required this.summary,
  });

  final String postId;
  final XContentMood mood;
  final Set<XContentTopic> topics;
  final Set<XContentColor> colors;
  final double weirdness;
  final double negativity;
  final double meme;
  final String summary;
}

@immutable
final class XMedia {
  const XMedia({
    required this.key,
    required this.type,
    required this.previewUrl,
    required this.downloadUrl,
    required this.playbackUrl,
    required this.contentType,
    required this.width,
    required this.height,
  });

  final String key;
  final String type;
  final Uri? previewUrl;
  final Uri? downloadUrl;
  final Uri? playbackUrl;
  final String contentType;
  final int? width;
  final int? height;
}

@immutable
final class XPost {
  const XPost({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.sensitive,
    required this.media,
    required this.authorId,
    required this.authorName,
    required this.authorUsername,
    required this.authorAvatarUrl,
  });

  final String id;
  final String text;
  final DateTime? createdAt;
  final bool sensitive;
  final List<XMedia> media;
  final String authorId;
  final String authorName;
  final String authorUsername;
  final Uri? authorAvatarUrl;
}

@immutable
final class XStoredMedia {
  const XStoredMedia({
    required this.id,
    required this.postId,
    required this.mediaKey,
    required this.filename,
    required this.contentType,
    required this.byteLength,
    required this.chunkCount,
    required this.sha256,
    required this.createdAt,
    required this.keyVersion,
  });

  final String id;
  final String postId;
  final String mediaKey;
  final String filename;
  final String contentType;
  final int byteLength;
  final int chunkCount;
  final String sha256;
  final DateTime createdAt;
  final int keyVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'postId': postId,
    'mediaKey': mediaKey,
    'filename': filename,
    'contentType': contentType,
    'byteLength': byteLength,
    'chunkCount': chunkCount,
    'sha256': sha256,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'keyVersion': keyVersion,
  };

  static XStoredMedia fromJson(Map<String, Object?> json) => XStoredMedia(
    id: json['id']! as String,
    postId: json['postId']! as String,
    mediaKey: json['mediaKey']! as String,
    filename: json['filename']! as String,
    contentType: json['contentType']! as String,
    byteLength: (json['byteLength'] as num).toInt(),
    chunkCount: (json['chunkCount'] as num).toInt(),
    sha256: json['sha256']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    keyVersion: (json['keyVersion'] as num).toInt(),
  );
}
