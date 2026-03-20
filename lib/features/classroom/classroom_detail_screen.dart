import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'stream_tab.dart';
import 'assessments_tab.dart';
import 'people_tab.dart';
import '../teacher_essentials/presentation/gradebook_screen.dart';
import '../teacher_essentials/presentation/bulk_upload_screen.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/providers/classroom_provider.dart';

class ClassroomDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const ClassroomDetailScreen({super.key, required this.id});

  @override
  ConsumerState<ClassroomDetailScreen> createState() =>
      _ClassroomDetailScreenState();
}

class _ClassroomDetailScreenState extends ConsumerState<ClassroomDetailScreen> {
  int _selectedIndex = 0;
  bool _sidebarOpen = true;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isTeacher = user?.role.name == 'teacher';
    final classroomAsync = ref.watch(classroomDetailProvider(widget.id));

    final screens = [
      StreamTab(classroomId: widget.id),
      AssessmentsTab(classroomId: widget.id),
      PeopleTab(classroomId: widget.id),
      if (isTeacher) ...[
        GradebookScreen(classroomId: int.parse(widget.id)),
        BulkUploadScreen(classroomId: int.parse(widget.id)),
      ],
    ];

    final tabs = [
      {'icon': Icons.dashboard_outlined, 'label': 'Stream'},
      {'icon': Icons.assignment_outlined, 'label': 'Classwork'},
      {'icon': Icons.people_outline, 'label': 'People'},
      if (isTeacher) ...[
        {'icon': Icons.assessment_outlined, 'label': 'Gradebook'},
        {'icon': Icons.file_download_outlined, 'label': 'Import Students'},
      ],
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // ── Top Bar ──────────────────────────────────────────────
          _buildTopBar(context, classroomAsync),

          // ── Body: Sidebar + Content ─────────────────────────────
          Expanded(
            child: Row(
              children: [
                // ── Collapsible Sidebar ───────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  width: _sidebarOpen ? 240 : 0,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: Color(0xFFE8E8E8)),
                    ),
                  ),
                  child: SizedBox(
                    width: 240,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Classroom name header
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(14, 16, 14, 10),
                          child: classroomAsync.when(
                            data: (classroom) => Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF8B1A24), // Maroon
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                  child: Image.asset(
                                    'assets/cite_logo.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    classroom.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF7B1FA2),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                        ),

                        // Navigation items
                        Expanded(
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.only(top: 4),
                            itemCount: tabs.length,
                            itemBuilder: (context, index) {
                              final isSelected =
                                  _selectedIndex == index;
                              final tab = tabs[index];
                              return _SidebarNavItem(
                                icon: tab['icon'] as IconData,
                                label: tab['label'] as String,
                                isSelected: isSelected,
                                showChevron:
                                    isSelected && index == 0,
                                onTap: () => setState(() =>
                                    _selectedIndex = index),
                              );
                            },
                          ),
                        ),

                        // User info at bottom
                        Container(
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE8E8E8)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    const Color(0xFF9068F5), // Softer purple
                                child: Icon(
                                  Icons.email_outlined,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      user?.email ?? 'user@email.com',
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF444444),
                                      ),
                                    ),
                                    const Text(
                                      'Signed in',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF999999),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Main Content Area ─────────────────────────────
                Expanded(
                  child: Container(
                    color: const Color(0xFFF5F5F5),
                    child: IndexedStack(
                        index: _selectedIndex,
                        children: screens),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
      BuildContext context, AsyncValue classroomAsync) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF7B1FA2),
            Color(0xFF9C27B0),
            Color(0xFFAB47BC),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Left actions + Logos + School Name
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                InkWell(
                  onTap: () => setState(() => _sidebarOpen = !_sidebarOpen),
                  child: const SizedBox(
                    width: 56,
                    height: 64,
                    child: Icon(
                      Icons.menu,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                Image.asset('assets/cite_logo.png', height: 34),
                const SizedBox(width: 8),
                Image.asset('assets/jmc_logo.png', height: 32),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'JOSE MARIA COLLEGE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'OldEnglish',
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Foundation, Inc.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Assured • Consistent • Quality Education',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 9,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Right actions
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.account_circle,
                      color: Colors.white, size: 28),
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar Navigation Item
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool showChevron;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.showChevron = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: isSelected
              ? Border.all(color: Colors.grey.shade300, width: 1.0)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF7B1FA2)
                  : const Color(0xFF666666),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFF7B1FA2)
                      : const Color(0xFF444444),
                  fontSize: 14,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (showChevron)
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF7B1FA2),
                size: 20,
              ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
