import 'dart:io';
import 'package:flutter/material.dart';
import '../../../providers/profile_provider.dart';

class BusinessCard extends StatelessWidget {
  final ProfileProvider profile;
  final dynamic user;
  final VoidCallback onEdit;
  final VoidCallback onPickImage;

  const BusinessCard({
    super.key,
    required this.profile,
    required this.user,
    required this.onEdit,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [profile.themeColor, profile.themeColor.withOpacity(0.5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: profile.themeColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildLogo(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.businessName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.ownerName.isEmpty
                          ? (user?.displayName ?? 'Business Owner')
                          : profile.ownerName,
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    if (profile.isActivated)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          profile.isLifetime ? 'LIFETIME PRO' : '${profile.remainingDays} DAYS LEFT',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: Colors.white24, height: 1),
          ),
          // Changed Row to Column for long address support
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoItem(Icons.phone_android_rounded, profile.contact),
              const SizedBox(height: 12),
              _infoItem(Icons.location_on_rounded, profile.address),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // Align icon with top of text
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Icon(icon, size: 14, color: Colors.white70),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text.isEmpty ? 'Not set' : text,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            // Removed maxLines to allow long address to wrap
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    final bool hasLocalLogo =
        profile.logoPath.isNotEmpty && File(profile.logoPath).existsSync();
    final String? userPhoto = user?.photoURL;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        GestureDetector(
          onTap: onPickImage,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
              image: hasLocalLogo
                  ? DecorationImage(
                      image: FileImage(File(profile.logoPath)),
                      fit: BoxFit.cover,
                    )
                  : (userPhoto != null
                      ? DecorationImage(
                          image: NetworkImage(userPhoto),
                          fit: BoxFit.cover,
                        )
                      : null),
            ),
            child: (!hasLocalLogo && userPhoto == null)
                ? Icon(Icons.storefront_rounded, size: 30, color: profile.themeColor)
                : null,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
          child: const Icon(Icons.edit_rounded, size: 10, color: Colors.white),
        ),
      ],
    );
  }
}
