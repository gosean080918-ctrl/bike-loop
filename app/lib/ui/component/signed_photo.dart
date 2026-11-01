import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../const/value/constants.dart';

/// Displays a photo from the private bucket: Storage path -> signed URL -> image
class SignedPhoto extends StatelessWidget {
  final String path;
  final double size;

  const SignedPhoto({super.key, required this.path, this.size = 56});

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return _fallback();
    return FutureBuilder<String>(
      future: Supabase.instance.client.storage
          .from(kPhotoBucket)
          .createSignedUrl(path, 3600),
      builder: (context, snap) {
        if (!snap.hasData) {
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snap.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        );
      },
    );
  }

  Widget _fallback() => SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.pedal_bike, size: 36, color: Colors.grey),
      );
}
