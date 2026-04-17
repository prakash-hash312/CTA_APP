import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../colors/app_color.dart';
import '../services/api_services.dart';
import 'homeworkdetailsscreen.dart';
import 'navbar_screen.dart';
import 'dart:developer';

class HomeWorkScreen extends StatefulWidget {
  const HomeWorkScreen({super.key});

  @override
  State<HomeWorkScreen> createState() => _HomeWorkScreenState();
}

class _HomeWorkScreenState extends State<HomeWorkScreen> {
  late Future<List<Map<String, dynamic>>> _homeworkFuture;
  final Dio _dio = Dio();

  @override
  void initState() {
    super.initState();
    _homeworkFuture = _loadHomework();
  }

  Future<List<Map<String, dynamic>>> _loadHomework() async {
    final prefs = await SharedPreferences.getInstance();
    int? profileStudentId;

    try {
      final profile = await apiService.viewProfile();
      if (profile.studentId > 0) {
        profileStudentId = profile.studentId;
      }
    } catch (e) {
      debugPrint('⚠️ Homework page could not resolve student id from profile: $e');
    }

    final candidateIds = <int>{
      if ((profileStudentId ?? 0) > 0) profileStudentId!,
      if ((apiService.currentStudentId ?? 0) > 0) apiService.currentStudentId!,
      if ((prefs.getInt('stud_id') ?? 0) > 0) prefs.getInt('stud_id')!,
      if ((apiService.currentUserId ?? 0) > 0) apiService.currentUserId!,
      if ((prefs.getInt('user_id') ?? 0) > 0) prefs.getInt('user_id')!,
    }.toList();

    if (candidateIds.isEmpty) {
      throw Exception('Student ID is not available for homework fetch');
    }

    final urls = <String>[
      'https://www.ivpsemi.in/CTA_Mob/v1/StudentHomeWork',
      'https://www.ivpsemi.in/CTA_Mob/v1/StudentHomework',
    ];

    String? lastMessage;
    int? lastStatusCode;

    for (final url in urls) {
      for (final id in candidateIds) {
        final queries = <Map<String, dynamic>>[
          {'Stud_id': id},
          {'stud_id': id},
        ];

        for (final query in queries) {
          try {
            debugPrint('📘 Homework page GET: $url');
            debugPrint('🧾 Homework page params: $query');

            final response = await _dio.get(
              url,
              queryParameters: query,
              options: Options(
                headers: {'Content-Type': 'application/json'},
                validateStatus: (status) => status != null && status < 600,
              ),
            );

            final data = response.data;
            debugPrint('✅ Homework page response ${response.statusCode}: $data');
            lastStatusCode = response.statusCode;

            if (response.statusCode == 200 && data is List) {
              return data.map((e) => Map<String, dynamic>.from(e)).toList();
            }

            if (response.statusCode == 204) {
              return [];
            }

            if (data is Map<String, dynamic>) {
              lastMessage = data['Message']?.toString() ??
                  data['message']?.toString() ??
                  'Server returned ${response.statusCode}';
            } else {
              lastMessage = 'Server returned ${response.statusCode}';
            }
          } catch (e) {
            debugPrint('❌ Homework page fetch failed for $query: $e');
            lastMessage = e.toString();
          }
        }
      }
    }

    final normalized = (lastMessage ?? '').toLowerCase().trim();
    if (lastStatusCode == 500 &&
        (normalized.isEmpty ||
            normalized == 'an error has occurred.' ||
            normalized == 'an error has occurred')) {
      debugPrint(
        '⚠️ Homework page fallback: generic server 500 for ids=$candidateIds, showing empty state.',
      );
      return [];
    }

    throw Exception(lastMessage ?? 'Failed to fetch homework');
  }

  Widget _buildDetailRow(String label, String value, {bool isRed = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LABEL COLUMN (fixed width → table-like alignment)
          SizedBox(
            width: 120, // 👈 controls alignment (adjust if needed)
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF5A5A5A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // VALUE COLUMN
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isRed ? Colors.red : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFE9F0FF),
        appBar: AppBar(
          elevation: 0, // r`emove default shadow
          title: Text('Homework Upload', style: TextStyle( fontWeight: FontWeight.w500),),
          centerTitle: true,
          backgroundColor: AppColors.appbarblue,
          foregroundColor: Colors.white,
          //iconTheme: IconThemeData(color: AppColors.kDarkText),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1.0),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Color(0xFFCAC5C5), // ← bottom border color
            ),
          ),
        ),
        drawer: NavbarScreen(),
        body: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _homeworkFuture = _loadHomework();
            });
            await _homeworkFuture;
          },
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _homeworkFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.kDarkBlue));
              } else if (snapshot.hasError) {
                return Center(
                  child: Text(
                    '❌ Error: ${snapshot.error}',
                    style: const TextStyle(color: AppColors.kErrorRed),
                  ),
                );
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text('No Homework Data Found'),
                );
              }
      
              final data = snapshot.data!;
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final hw = data[index];
                  final dueDate = hw['due_date']?.toString().split('T').first ?? '-';
                  final dueDateStr = hw['due_date']?.toString() ?? '';
                  final submittedDateStr = hw['submitted_date']?.toString() ?? '';
                  String displayStatus = hw['status']?.toString() ?? '-';
                  bool isLate = false;
      
                  if (submittedDateStr.isNotEmpty && dueDateStr.isNotEmpty) {
                    final due = DateTime.tryParse(dueDateStr);
                    final submitted = DateTime.tryParse(submittedDateStr);
      
                    if (due != null && submitted != null) {
                      if (submitted.isAfter(due)) {
                        displayStatus = 'Turned In Late';
                        isLate = true;
                      } else {
                        displayStatus = 'Turned In';
                      }
                    }
                  }
      
                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Header with blue background and rounded top
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0A3D91), Color(0xFF1565C0)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(14),
                              topRight: Radius.circular(14),
                            ),
                          ),
                          child: Text(
                            hw['week_name'] ?? 'WEEK',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
      
                        // Content area with light background
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4F8),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                            ),
                          ),
                          // decoration: const BoxDecoration(
                          //   color: Color(0xFFD9E8F7),   // SAME BLUE AS DETAIL SCREEN
                          //   borderRadius: BorderRadius.only(
                          //     bottomLeft: Radius.circular(16),
                          //     bottomRight: Radius.circular(16),
                          //   ),
                          // ),
      
      
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              _buildDetailRow('Name:', hw['stud_name']?.toString() ?? '-'),
                              _buildDetailRow('Student ID:', hw['stud_id']?.toString() ?? '-'),
                              _buildDetailRow('Batch:', hw['batch']?.toString() ?? '-'),
                              _buildDetailRow('School:', hw['school_site_name']?.toString() ?? '-'),
                              _buildDetailRow('Grade:', hw['grade_name']?.toString() ?? '-'),
                              _buildDetailRow('Section:', hw['section_name']?.toString() ?? '-'),
                              _buildDetailRow('Week Name:', hw['week_name']?.toString() ?? '-'),
                              _buildDetailRow('Status:', displayStatus, isRed: isLate),
                              _buildDetailRow('Due Date:', dueDate),
                              _buildDetailRow('Submitted Date:', hw['submitted_date']?.toString().split('T').first ?? '-'),
      
                              const SizedBox(height: 16),
      
                              // View Homework Details Button
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      // gradient: const LinearGradient(
                                      //   colors: [Color(0xFF2B57A0), Color(0xFF13345F)],
                                      //   begin: Alignment.topLeft,
                                      //   end: Alignment.bottomRight,
                                      // ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: ElevatedButton(
                                      onPressed: () {
                                        final hwType = hw['hw_type']?.toString().isNotEmpty == true
                                            ? hw['hw_type'].toString()
                                            : 'Regular Homework';
      
                                        final studId = int.tryParse(hw['stud_id'].toString()) ?? 0;
                                        final batch = int.tryParse(hw['batch'].toString()) ?? 0;
                                        final weekId = int.tryParse(hw['week_id'].toString()) ?? 0;
      
                                        debugPrint('📖 View Homework: ${hw['hw_subject']}');
      
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => HomeworkDetailScreen(
                                              hwAssignId: hw['hw_assign_id'],
                                              hwContentId: hw['hw_content_id'] ?? 0,
                                              hwType: hwType,
                                              studId: studId,
                                              batch: batch,
                                              weekId: weekId,
                                              dueDate: dueDate,
                                            ),
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        backgroundColor: Colors.blue.shade900, // important for gradient
                                        shadowColor: Colors.transparent,    // remove shadow
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Text(
                                            'View Homework Details',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(
                                            Icons.arrow_forward_ios,
                                            color: Colors.white,
                                            size: 17,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
      
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
