import 'dart:io';
import 'package:flutter/material.dart';

class MemeDetailScreen extends StatelessWidget {
  /// The unique tag for the Hero animation.
  final String heroTag;
  
  /// The URL if it's a cloud image.
  final String? imageUrl;
  
  /// The local file path if it's a local draft.
  final String? localPath;

  const MemeDetailScreen({
    super.key,
    required this.heroTag,
    this.imageUrl,
    this.localPath,
  }) : assert(imageUrl != null || localPath != null); // Must provide one image source

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 1. A black background is standard for "lightbox" views
      backgroundColor: Colors.black,
      body: GestureDetector(
        // 2. Tapping anywhere on the screen will close it
        onTap: () {
          Navigator.pop(context);
        },
        child: Center(
          // 3. This is the "destination" Hero widget
          child: Hero(
            tag: heroTag,
            child: localPath != null
                // It's a local draft
                ? Image.file(
                    File(localPath!),
                    fit: BoxFit.contain, // Shows the WHOLE image
                  )
                // It's a cloud post
                : Image.network(
                    imageUrl!,
                    fit: BoxFit.contain, // Shows the WHOLE image
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) =>
                        const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 100,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}