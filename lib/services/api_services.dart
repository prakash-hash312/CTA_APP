// lib/services/api_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dropdownmodel.dart';

import '../models/usermodel.dart'; // âœ… use the final UserProfile model name you saved earlier

// --- API ENDPOINTS ---
const String kBaseUrl = 'https://www.ivpsemi.in/CTA_Mob/v1';
const String kLoginUrl = '$kBaseUrl/Login';
const String kViewProfileUrl = '$kBaseUrl/ViewProfile';
const String kModifyProfileUrl = '$kBaseUrl/ModifyProfile';
const String kChangePasswordUrl = '$kBaseUrl/ChangePassword';
const String kMenuUrl = '$kBaseUrl/Menu';
const String kThemeListUrl = '$kBaseUrl/Theme';
const String kGenderListUrl = '$kBaseUrl/Gender';
const String kStateListUrl = '$kBaseUrl/State';
const String kStudentHomeworkUrl = '$kBaseUrl/StudentHomework';
const String kStudentHomeWorkUrl = '$kBaseUrl/StudentHomeWork';
const String kSyllabusHwBaseUrl = 'https://www.ivpsemi.in/CTA_Mob/api/HW';

class ApiService {
  final Dio _dio = Dio();
  String? _authToken;
  String? _cookieHeader;
  int? _currentUserId; // stored after login
  int? _currentEmpId; // optional empid for Menu API
  int? _currentStudId; // resolved student id for syllabus APIs
  String? _currentUsername; // âœ… store username persistently
  String? _currentLoginEmail; // email used at login

  /// Set bearer token to include in subsequent requests
  void setAuthToken(String? token) {
    _authToken = token;
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  /// Set Cookie header for session-based auth (if your backend uses cookies)
  void setCookieHeader(String? cookie) {
    _cookieHeader = cookie;
    if (cookie != null && cookie.isNotEmpty) {
      _dio.options.headers['Cookie'] = cookie;
    } else {
      _dio.options.headers.remove('Cookie');
    }
  }

  bool get isLoggedIn => _currentUserId != null;
  String? get currentUsername => _currentUsername; // âœ… getter
  String? get currentLoginEmail => _currentLoginEmail;
  // ----------------- COMMON HELPERS -----------------
  void setCurrentUserId(int userId) => _currentUserId = userId;

  void setCurrentEmpId(int? empId) => _currentEmpId = empId;

  int? get currentEmpId => _currentEmpId;
  int? get currentStudentId => _currentStudId;

  int? get currentUserId => _currentUserId;

  // Future<dynamic> _get(String url, {Map<String, dynamic>? queryParameters}) async {
  //   try {
  //     final response = await _dio.get(
  //       url,
  //       queryParameters: queryParameters,
  //       options: Options(headers: {'Content-Type': 'application/json'}),
  //     );
  //     return response.data;
  //   } on DioException catch (e) {
  //     debugPrint('GET Error on $url: ${e.response?.statusCode} - ${e.message}');
  //     throw Exception('Failed to load data: ${e.response?.data?['message'] ?? e.message}');
  //   }
  // }

  // âœ… Load user session on app start
  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', _currentUserId ?? 0);
    await prefs.setInt('emp_id', _currentEmpId ?? 0);
    await prefs.setInt('stud_id', _currentStudId ?? 0);
    await prefs.setString('username', _currentUsername ?? '');
    await prefs.setString('login_email', _currentLoginEmail ?? '');
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getInt('user_id');
    _currentEmpId = prefs.getInt('emp_id');
    _currentStudId = prefs.getInt('stud_id');
    _currentUsername = prefs.getString('username');
    _currentLoginEmail = prefs.getString('login_email');
    // Load optional persisted auth token or cookie (if your app saved them)
    final savedToken = prefs.getString('auth_token');
    final savedCookie = prefs.getString('cookie');
    if (savedToken != null && savedToken.isNotEmpty) setAuthToken(savedToken);
    if (savedCookie != null && savedCookie.isNotEmpty) setCookieHeader(savedCookie);
    debugPrint('ðŸ”¹ Session loaded: user_id=$_currentUserId, username=$_currentUsername');
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _currentUserId = null;
    _currentEmpId = null;
    _currentStudId = null;
    _currentUsername = null;
    _currentLoginEmail = null;
    debugPrint('ðŸšª User logged out. Session cleared.');
  }
  /// Resolve and persist the student id used by syllabus endpoints.
  Future<int?> ensureCurrentStudentId() async {
    if (_currentStudId != null && _currentStudId! > 0) return _currentStudId;
    if (_currentUserId == null || _currentUserId! <= 0) return null;

    try {
      final rows = await fetchStudentHomeWork(studId: _currentUserId);
      for (final row in rows) {
        final sid = int.tryParse('${row['stud_id'] ?? 0}') ?? 0;
        if (sid > 0) {
          _currentStudId = sid;
          await _saveSession();
          return _currentStudId;
        }
      }
    } catch (_) {
      // Fallback below.
    }

    _currentStudId = _currentUserId;
    await _saveSession();
    return _currentStudId;
  }
  Future<Response> _getResponse(String url,
      {Map<String, dynamic>? queryParameters}) async {
    try {
      debugPrint('?? GET Request: $url');
      debugPrint('?? Query Params: $queryParameters');

      final response = await _dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          followRedirects: true,
          validateStatus: (status) => status! < 500,
        ),
      );

      debugPrint('? Response Code: ${response.statusCode}');
      debugPrint('? Response Data: ${response.data}');
      return response;
    } on DioException catch (e) {
      debugPrint('? Dio GET Error on $url: ${e.message}');
      if (e.response != null) debugPrint('Response: ${e.response}');
      throw Exception('Failed to load data: ${e.message}');
    }
  }

  Future<dynamic> _get(String url,
      {Map<String, dynamic>? queryParameters}) async {
    try {
      debugPrint('ðŸŒ GET Request: $url');
      debugPrint('ðŸ§¾ Query Params: $queryParameters');

      final response = await _dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          followRedirects: true,
          validateStatus: (status) => status! < 500,
        ),
      );

      debugPrint('âœ… Response Code: ${response.statusCode}');
      debugPrint('âœ… Response Data: ${response.data}');
      return response.data;
    } on DioException catch (e) {
      debugPrint('âŒ Dio GET Error on $url: ${e.message}');
      if (e.response != null) debugPrint('Response: ${e.response}');
      throw Exception('Failed to load data: ${e.message}');
    }
  }


  Future<Map<String, dynamic>> _post(String url,
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(
        url,
        data: data,
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : jsonDecode(response.data);
    } on DioException catch (e) {
      debugPrint(
          'POST Error on $url: ${e.response?.statusCode} - ${e.message}');
      throw Exception(
          'Failed to process request: ${e.response?.data?['message'] ??
              e.message}');
    }
  }

  // ----------------- API CALLS -----------------

  /// 1ï¸âƒ£ LOGIN (GET)
  Future<UserProfile> login(String username, String password) async {
    final responseData = await _get(kLoginUrl, queryParameters: {
      'empno': username,
      'password': password,
    });

    if (responseData is List && responseData.isNotEmpty) {
      final user = UserProfile.fromJson(responseData[0]);
      setCurrentUserId(user.userId);
      _currentEmpId = user.userId;
      _currentUsername = user.userName ?? username; // âœ… Save username
      _currentLoginEmail =
          user.userEmailId.isNotEmpty ? user.userEmailId : username;
      await ensureCurrentStudentId();

      // âœ… Save login details
      await _saveSession();
      return user;
    }
    throw Exception('Login failed: invalid credentials or empty response.');
  }

  /// 2ï¸âƒ£ VIEW PROFILE (GET)
  Future<UserProfile> viewProfile() async {
    if (_currentUserId == null) throw Exception('User not logged in.');
    if (_currentLoginEmail == null || _currentLoginEmail!.isEmpty) {
      throw Exception('Login email not available for ViewProfile API.');
    }
    // ðŸ’¡ Add this line
    debugPrint('ðŸ”¹ Fetching profile for empid=$_currentUserId');

    final responseData = await _get(kViewProfileUrl, queryParameters: {
      'empid': _currentUserId, // âœ… correct param as per your API
      'email': _currentLoginEmail,
    });

    debugPrint('âœ… Response: $responseData');

    if (responseData is List && responseData.isNotEmpty) {
      return UserProfile.fromJson(responseData[0]);
    }
    throw Exception('Failed to load profile data.');
  }

  /// 3ï¸âƒ£ MODIFY PROFILE (POST)
  Future<String> modifyProfile(Map<String, dynamic> requestData) async {
    if (_currentUserId == null) throw Exception('User not logged in.');
    requestData['user_id'] = _currentUserId;

    final response = await _post(kModifyProfileUrl, requestData);

    if (response['success'] == true) {
      return response['message'] ?? 'Profile updated successfully!';
    }
    throw Exception('Profile update failed: ${response['message']}');
  }

  /// 4ï¸âƒ£ CHANGE PASSWORD (POST)
  Future<String> changePassword(String newPwd,
      String confirmPwd,
      String oldPwd,) async {
    if (_currentUserId == null) throw Exception('User not logged in.');

    final requestData = {
      "new_pwd": newPwd,
      "confirm_pwd": confirmPwd,
      "old_pwd": oldPwd,
      "is_parent2": "No", // âœ… matches your backend (Postman version)
      "user_id": _currentUserId,
    };

    try {
      debugPrint('ðŸ” Sending change password request...');

      final response = await _post(kChangePasswordUrl, requestData);

      debugPrint('âœ… Password API response: $response');

      // âœ… Safely parse response regardless of format
      if (response is Map<String, dynamic>) {
        if (response['success'] == true ||
            response['Success'] == true) {
          return response['message'] ??
              response['Message'] ??
              'Password changed successfully!';
        } else {
          throw Exception(
              response['message'] ??
                  response['Message'] ??
                  'Password change failed.');
        }
      } else {
        throw Exception('Unexpected response format from server.');
      }
    } on Exception catch (e) {
      // âœ… Handle 404, network, timeout gracefully
      final err = e.toString();
      if (err.contains('404')) {
        throw Exception(
            'Password change service not found (404). Please check API path.');
      } else if (err.contains('Failed host lookup')) {
        throw Exception('No internet connection.');
      } else if (err.contains('timeout')) {
        throw Exception('Server timeout. Try again later.');
      } else {
        rethrow;
      }
    }
  }


  /// 5ï¸âƒ£ MENU LIST (GET)
  Future<List<MenuItem>> fetchMenuList({String? email}) async {
    final empId = _currentEmpId ?? _currentUserId;
    if (empId == null) throw Exception('User not logged in.');
    final resolvedEmail = (email != null && email.isNotEmpty)
        ? email
        : (_currentLoginEmail ?? '');
    if (resolvedEmail.isEmpty) {
      throw Exception('Login email not available for Menu API.');
    }
    final responseData = await _get(
        kMenuUrl, queryParameters: {
          'empid': empId,
          'email': resolvedEmail,
        });
    if (responseData is List) {
      return responseData.map((json) => MenuItem.fromJson(json)).toList();
    }
    return [];
  }

  /// 6ï¸âƒ£ THEME LIST (GET)
  Future<List<ThemeItem>> fetchThemeList() async {
    final responseData = await _get(kThemeListUrl);
    if (responseData is List) {
      return responseData.map((json) => ThemeItem.fromJson(json)).toList();
    }
    return [];
  }

  /// 7ï¸âƒ£ GENDER LIST (GET)
  Future<List<GenderItem>> fetchGenderList() async {
    final responseData = await _get(kGenderListUrl);
    if (responseData is List) {
      return responseData.map((json) => GenderItem.fromJson(json)).toList();
    }
    return [];
  }

  /// 8ï¸âƒ£ STATE LIST (GET)
  Future<List<StateItem>> fetchStateList() async {
    final responseData = await _get(kStateListUrl);
    if (responseData is List) {
      return responseData.map((json) => StateItem.fromJson(json)).toList();
    }
    return [];
  }

  /// 9ï¸âƒ£ STATIC HOMEWORK API (no user_id or login dependency)
  /// 9ï¸âƒ£ STATIC HOMEWORK API (No login or user dependency)
  Future<List<Map<String, dynamic>>> fetchStudentHomeWork({int? studId}) async {
    const String url = 'https://www.ivpsemi.in/CTA_Mob/v1/StudentHomeWork';
    final resolvedStudId = studId ?? _currentStudId ?? _currentUserId ?? 19233;

    try {
      final responseData = await _get(
        url,
        queryParameters: {'Stud_id': resolvedStudId},
      );

      debugPrint('ðŸ“˜ Homework API response: $responseData');

      if (responseData is List) {
        // Ensure every element is a Map<String, dynamic>
        return responseData.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        debugPrint('âš ï¸ Unexpected API format: $responseData');
        return [];
      }
    } catch (e) {
      debugPrint('âŒ Homework fetch error: $e');
      throw Exception('Failed to fetch homework');
    }
  }

  /// 10ï¸âƒ£ SYLLABUS GRADE INFO (GET)
  Future<List<Map<String, dynamic>>> fetchSyllabusGradeInfo({
    required int studId,
  }) async {
    const String url = '$kSyllabusHwBaseUrl/GradeInfo';
    final responseData = await _get(url, queryParameters: {'stud_id': studId});
    if (responseData is List) {
      return responseData.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  /// 11ï¸âƒ£ SYLLABUS TOPIC INFO (GET)
  Future<List<Map<String, dynamic>>> fetchSyllabusTopicInfo({
    required int mainId,
  }) async {
    const String url = '$kSyllabusHwBaseUrl/TopicInfo';
    final responseData = await _get(url, queryParameters: {'main_id': mainId});
    if (responseData is List) {
      return responseData.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  /// 12ï¸âƒ£ SYLLABUS SUBTOPIC INFO (GET)
  Future<List<Map<String, dynamic>>> fetchSyllabusSubTopicInfo({
    required int topicId,
  }) async {
    const String url = '$kSyllabusHwBaseUrl/SubTopicInfo';
    final responseData = await _get(url, queryParameters: {'topic_id': topicId});
    if (responseData is List) {
      return responseData.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  /// 13ï¸âƒ£ SYLLABUS CONTENT (GET)
  Future<List<Map<String, dynamic>>> fetchSyllabusContent({
    required int subtopicId,
  }) async {
    const String url = '$kSyllabusHwBaseUrl/Content';
    final responseData = await _get(
      url,
      queryParameters: {'SubSubTopicID': subtopicId},
    );
    if (responseData is List) {
      return responseData.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  /// ðŸ”Ÿ HOMEWORK DETAIL API
  Future<List<Map<String, dynamic>>> fetchHomeworkDetail({
    required int hwContentId,
    required String hwType,
  }) async {
    const String url = 'https://www.ivpsemi.in/CTA_Mob/v1/GetHwContent';
    try {
      final responseData = await _get(url, queryParameters: {
        'hw_content_id': hwContentId,
        'hw_type': hwType,
      });

      debugPrint('ðŸ“˜ Homework Detail API response: $responseData');

      if (responseData is List) {
        return responseData.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        debugPrint('âš ï¸ Unexpected detail format: $responseData');
        return [];
      }
    } catch (e) {
      debugPrint('âŒ Homework detail fetch error: $e');
      throw Exception('Failed to fetch homework details');
    }
  }


  /// ðŸ§© UPLOAD HOMEWORK FILES
  Future<Map<String, dynamic>> uploadHomeworkFiles({
    required int studentId,
    required int batch,
    required int weekId,
    required String homeworkType,
    required List<File> files,
  }) async {
    const String url = 'https://www.ivpsemi.in/CTA_Mob/v1/FileUpload';

    try {
      final formData = FormData();

      // Add all files under key 'file'
      for (var file in files) {
        formData.files.add(MapEntry(
          'file',
          await MultipartFile.fromFile(
            file.path,
            filename: file.path
                .split('/')
                .last,
          ),
        ));
      }

      // Add required form fields
      formData.fields.addAll([
        MapEntry('StudentId', studentId.toString()),
        MapEntry('Batch', batch.toString()),
        MapEntry('WeekId', weekId.toString()),
        MapEntry('HomeworkType', homeworkType.trim()),
      ]);

      debugPrint('ðŸ“¤ Uploading files â†’ $url');
      debugPrint('ðŸ§¾ Fields: ${formData.fields}');
      debugPrint('ðŸ“¦ Files count: ${files.length}');

      final response = await _dio.post(
        url,
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
        onSendProgress: (sent, total) {
          if (total > 0) {
            final progress = (sent / total * 100).toStringAsFixed(1);
            debugPrint('â³ Upload progress: $progress%');
          }
        },
      );

      debugPrint('âœ… Upload Response: ${response.data}');
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data;
      } else {
        throw Exception(response.data['message'] ?? 'Upload failed.');
      }
    } catch (e) {
      debugPrint('âŒ Upload error: $e');
      throw Exception('Failed to upload files: $e');
    }
  }


  /// ðŸ§¾ GET UPLOADED HOMEWORK FILES
  Future<List<Map<String, dynamic>>> fetchUploadedHomeworkFiles({
    required int hwAssignId,
    required String hwType,
  }) async {
    const String baseUrl = 'https://www.ivpsemi.in/CTA_Mob/v1/GetHwUploadedFiles';
    try {
      debugPrint('ðŸ“¥ [GetUploadedFiles] Fetching uploaded files...');
      debugPrint('ðŸ”¹ hw_assign_id: $hwAssignId');
      debugPrint('ðŸ”¹ hw_type: $hwType');


      final response = await _dio.get(
        baseUrl,
        queryParameters: {
          'hw_assign_id': hwAssignId,
          'hw_type': hwType.trim().isEmpty ? 'Regular Homework' : hwType.trim(),
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => true,
        ),
      );

      debugPrint('ðŸ“¥ [GetUploadedFiles] Status: ${response.statusCode}');
      debugPrint('ðŸ“¥ [GetUploadedFiles] Response: ${response.data}');

      if (response.statusCode == 200 && response.data is List) {
        debugPrint(
            'âœ… [GetUploadedFiles] Files received: ${response.data.length}');
        return List<Map<String, dynamic>>.from(response.data);
      } else if (response.statusCode == 204) {
        debugPrint('â„¹ï¸ [GetUploadedFiles] No files found for this homework.');
        return [];
      } else {
        throw Exception(response.data['message'] ?? 'Unknown error');
      }
    } catch (e) {
      debugPrint('âŒ [GetUploadedFiles] Error: $e');
      throw Exception('Failed to fetch uploaded homework files: $e');
    }
  }


  Future<String> draftHomework({
    required String hwType,
    required int batch,
    required int weekId,
    required int studId,
    required int hwAssignId,
    required int userId,
    required List<String> uploadedFiles,
  }) async {
    const url = 'https://www.ivpsemi.in/CTA_Mob/v1/DraftHomework';
    final data = {
      "HwType": hwType,
      "Batch": batch,
      "WeekId": weekId,
      "StudId": studId,
      "HwAssignId": hwAssignId,
      "UserId": userId,
      "UploadedFiles": uploadedFiles.map((f) => {"FileName": f}).toList(),
    };

    debugPrint('ðŸ“ [DraftHomework] Sending draft...');
    debugPrint('ðŸ“¦ Data: $data');

    try {
      final response = await _post(url, data);
      debugPrint('âœ… [DraftHomework] Response: $response');

      if (response['success'] == true) {
        debugPrint('âœ… [DraftHomework] Draft saved successfully.');
        return response['message'] ?? 'Draft saved successfully!';
      } else {
        debugPrint('âŒ [DraftHomework] Failed: ${response['message']}');
        throw Exception(response['message'] ?? 'Failed to draft homework.');
      }
    } catch (e) {
      debugPrint('âŒ [DraftHomework] Exception: $e');
      throw Exception('Failed to draft homework: $e');
    }
  }


  // Future<String> turnInHomework({
  //   required String hwType,
  //   required int batch,
  //   required int weekId,
  //   required int studId,
  //   required int hwAssignId,
  //   required int userId,
  //   required List<String> uploadedFiles,
  //
  // }) async {
  //   const url = 'https://www.ivpsemi.in/CTA_Mob/v1/TurnInHomework';
  //
  //
  //   final now = DateTime.now().toIso8601String();
  //
  //   final data = {
  //     "HwType": hwType,
  //     "Batch": batch,
  //     "WeekId": weekId,
  //     "StudId": studId,
  //     "HwAssignId": hwAssignId,
  //     "UserId": userId,
  //     "SubmittedDate": now,
  //     "UploadedFiles": uploadedFiles.map((f) => {"FileName": f}).toList(),
  //   };
  //
  //
  //   debugPrint('ðŸ“¤ [TurnInHomework] Turning in homework...');
  //   debugPrint('ðŸ“¦ Data: $data');
  //
  //   try {
  //     final response = await _post(url, data);
  //     debugPrint('âœ… [TurnInHomework] Response: $response');
  //
  //     if (response['success'] == true) {
  //       debugPrint(
  //           'âœ… [TurnInHomework] Success message: ${response['message']}');
  //       return response['message'] ?? 'Homework turned in successfully!';
  //     } else {
  //       debugPrint('âŒ [TurnInHomework] Failed: ${response['message']}');
  //       throw Exception(response['message'] ?? 'Failed to turn in homework.');
  //     }
  //   } catch (e) {
  //     debugPrint('âŒ [TurnInHomework] Exception: $e');
  //     throw Exception('Failed to turn in homework: $e');
  //   }
  // }

  Future<Map<String, dynamic>> turnInHomework({
    required String hwType,
    required int batch,
    required int weekId,
    required int studId,
    required int hwAssignId,
    required int userId,
    required List<String> uploadedFiles,
  }) async {
    const String url = 'https://www.ivpsemi.in/CTA_Mob/v1/TurnInHomework';

    final payload = {
      "HwType": hwType,
      "Batch": batch,
      "WeekId": weekId,
      "StudId": studId,
      "HwAssignId": hwAssignId,
      "UserId": userId,
      "UploadedFiles": uploadedFiles.map((f) => {"FileName": f}).toList(),
    };

    debugPrint('ðŸ“¦ [TurnInHomework] Payload â†’ $payload');

    final response = await _dio.post(
      url,
      data: payload,
      options: Options(headers: {'Content-Type': 'application/json'}),
    );

    debugPrint('âœ… [TurnInHomework] Response: ${response.data}');
    return response.data;
  }

  /// Download raw bytes using the shared Dio instance.
  /// Returns the Dio Response<List<int>> so caller can inspect status and data.
  Future<Response<List<int>>> downloadFileBytes(String url) async {
    try {
      debugPrint('ðŸ“¥ [downloadFileBytes] Downloading: $url');
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes, followRedirects: true, validateStatus: (s) => s! < 500),
      );
      debugPrint('ðŸ“¥ [downloadFileBytes] Status: ${response.statusCode}');
      return response;
    } on DioException catch (e) {
      debugPrint('âŒ [downloadFileBytes] Error: ${e.message}');
      rethrow;
    }
  }

  /// ðŸ—‘ï¸ DELETE HOMEWORK FILE
  /// ðŸ—‘ï¸ DELETE HOMEWORK FILE (Using POST as per server configuration)
  /// ðŸ—‘ï¸ DELETE HOMEWORK FILE (Using existing _post helper)
  /// ðŸ—‘ï¸ DELETE HOMEWORK FILE - Debug version
  /// ðŸ—‘ï¸ DELETE HOMEWORK FILE - Using FormData
  /// ðŸ—‘ï¸ DELETE HOMEWORK FILE (Using proper DELETE method)
  /// ðŸ—‘ï¸ DELETE HOMEWORK FILE (Using request method)
  /// ðŸ—‘ï¸ DELETE HOMEWORK FILE (Using DELETE with query parameters)
  /// ðŸ—‘ï¸ DELETE HOMEWORK FILE (Alternative: Using GET)
  // Future<Map<String, dynamic>> deleteHomeworkFile({
  //   required String homeworkType,
  //   required int batch,
  //   required int weekId,
  //   required int studId,
  //   required String fileName,
  // }) async {
  //   const String baseUrl = 'https://www.ivpsemi.in/CTA_Mob/v1/FileDelete';
  //
  //   try {
  //     final queryParams = {
  //       'HomeworkType': homeworkType.trim(),
  //       'Batch': batch.toString(),
  //       'WeekId': weekId.toString(),
  //       'StudId': studId.toString(),
  //       'FileName': fileName,
  //     };
  //
  //     debugPrint('ðŸ—‘ï¸ [DeleteFile] Trying with GET method');
  //     debugPrint('ðŸ—‘ï¸ [DeleteFile] Query Params: $queryParams');
  //
  //     final response = await _dio.get(
  //       baseUrl,
  //       queryParameters: queryParams,
  //       options: Options(
  //         headers: {'Accept': 'application/json'},
  //         validateStatus: (status) => true,
  //       ),
  //     );
  //
  //     debugPrint('ðŸ“ Status: ${response.statusCode}');
  //
  //     // Check for HTML error response
  //     if (response.data is String && response.data.toString().contains('<!DOCTYPE')) {
  //       return {
  //         "success": false,
  //         "message": "Invalid endpoint or method"
  //       };
  //     }
  //
  //     debugPrint('ðŸ“ Response: ${response.data}');
  //
  //     if (response.statusCode == 200) {
  //       if (response.data is Map) {
  //         return response.data;
  //       }
  //       return {"success": true, "message": "File deleted"};
  //     }
  //
  //     return {
  //       "success": false,
  //       "message": "Failed (Status: ${response.statusCode})"
  //     };
  //
  //   } catch (e) {
  //     debugPrint('âŒ Error: $e');
  //     return {
  //       "success": false,
  //       "message": "Error: ${e.toString()}"
  //     };
  //   }
  // }

  Future<Map<String, dynamic>> deleteHomeworkFile({
    required String homeworkType,
    required int batch,
    required int weekId,
    required int studId,
    required String fileName,
  }) async {
    const String url = 'https://www.ivpsemi.in/CTA_Mob/v1/FileDelete';

    final payload = {
      "HomeworkType": homeworkType.trim().isEmpty ? "Regular Homework" : homeworkType.trim(),
      "Batch": batch,
      "WeekId": weekId,
      "StudId": studId,
      "FileName": fileName.trim(),
    };

    debugPrint('ðŸ—‘ï¸ [DeleteFile] DELETE payload: $payload');

    try {
      final response = await _dio.request(
        url,
        data: payload,
        options: Options(
          method: 'DELETE',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            // Authorization header is usually set globally; keep it if needed
          },
          validateStatus: (_) => true,
        ),
      );

      debugPrint('ðŸ—‘ï¸ [DeleteFile] Status: ${response.statusCode}');
      debugPrint('ðŸ—‘ï¸ [DeleteFile] Data: ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        // If response.data is already a Map with success key, return it; otherwise create one.
        if (response.data is Map<String, dynamic>) {
          return Map<String, dynamic>.from(response.data);
        } else {
          return {
            "success": true,
            "message": response.data?.toString() ?? 'Deleted (no body)'
          };
        }
      }

      // Non-success
      return {
        "success": false,
        "statusCode": response.statusCode,
        "message": response.data?.toString() ?? 'Unexpected response'
      };
    } catch (e) {
      debugPrint('âŒ [DeleteFile] Exception: $e');
      return {"success": false, "message": "Exception: $e"};
    }


}



}





// ðŸŒ Global instance to access everywhere
final apiService = ApiService();

