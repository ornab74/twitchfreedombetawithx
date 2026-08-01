import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/x/x_api.dart';
import 'package:twitch_freedom_ultra/x/x_media_store.dart';

void main() {
  test('timeline parser separates smooth playback and full download MP4s', () {
    final posts = XApiService.parseTimeline(<String, Object?>{
      'data': <Object?>[
        <String, Object?>{
          'id': '42',
          'text': 'video post',
          'created_at': '2026-01-01T00:00:00Z',
          'author_id': '99',
          'attachments': <String, Object?>{
            'media_keys': <String>['7_9'],
          },
        },
      ],
      'includes': <String, Object?>{
        'users': <Object?>[
          <String, Object?>{
            'id': '99',
            'name': 'Test Author',
            'username': 'test_author',
            'profile_image_url': 'https://pbs.twimg.com/profile_images/a.jpg',
          },
        ],
        'media': <Object?>[
          <String, Object?>{
            'media_key': '7_9',
            'type': 'video',
            'preview_image_url': 'https://pbs.twimg.com/media/preview.jpg',
            'variants': <Object?>[
              <String, Object?>{
                'content_type': 'application/x-mpegURL',
                'url': 'https://video.twimg.com/a.m3u8',
              },
              <String, Object?>{
                'content_type': 'video/mp4',
                'bit_rate': 256000,
                'url': 'https://video.twimg.com/low.mp4',
              },
              <String, Object?>{
                'content_type': 'video/mp4',
                'bit_rate': 2176000,
                'url': 'https://video.twimg.com/high.mp4',
              },
              <String, Object?>{
                'content_type': 'video/mp4',
                'bit_rate': 832000,
                'url': 'https://video.twimg.com/smooth.mp4',
              },
            ],
          },
        ],
      },
    });

    expect(posts, hasLength(1));
    expect(
      posts.single.media.single.playbackUrl.toString(),
      'https://video.twimg.com/smooth.mp4',
    );
    expect(
      posts.single.media.single.downloadUrl.toString(),
      'https://video.twimg.com/high.mp4',
    );
    expect(posts.single.authorName, 'Test Author');
    expect(posts.single.authorUsername, 'test_author');
  });

  test('media URL policy only permits exact TLS X media hosts', () {
    expect(
      XMediaStore.isTrustedMediaUri(
        Uri.parse('https://video.twimg.com/path/video.mp4'),
      ),
      isTrue,
    );
    expect(
      XMediaStore.isTrustedMediaUri(
        Uri.parse('https://pbs.twimg.com/media/photo.jpg'),
      ),
      isTrue,
    );
    expect(
      XMediaStore.isTrustedMediaUri(
        Uri.parse('http://video.twimg.com/path/video.mp4'),
      ),
      isFalse,
    );
    expect(
      XMediaStore.isTrustedMediaUri(
        Uri.parse('https://video.twimg.com.evil.example/video.mp4'),
      ),
      isFalse,
    );
    expect(
      XMediaStore.isTrustedMediaUri(
        Uri.parse('https://user@video.twimg.com/video.mp4'),
      ),
      isFalse,
    );
  });
}
