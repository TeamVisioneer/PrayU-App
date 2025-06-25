import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:flutter/material.dart';

class ImageDownloadService {
  static final Dio _dio = Dio();

  /// 단일 이미지를 다운로드하고 갤러리에 저장하는 함수
  static Future<bool> downloadImageToGallery(String imageUrl) async {
    try {
      // 1. 권한 확인 및 요청
      if (!await _requestPermissions()) {
        return false;
      }

      // 2. 이미지 다운로드
      final Uint8List? imageBytes = await _downloadImage(imageUrl);
      if (imageBytes == null) {
        return false;
      }

      // 3. 갤러리에 저장
      return await _saveImageToGallery(imageBytes);
    } catch (e) {
      return false;
    }
  }

  /// 여러 이미지를 동시에 다운로드하고 갤러리에 저장하는 함수
  static Future<Map<String, dynamic>> downloadMultipleImagesToGallery(
    List<String> imageUrls, {
    int maxConcurrent = 3, // 동시 다운로드 제한
    Duration delayBetweenDownloads = const Duration(milliseconds: 500),
  }) async {
    debugPrint(
        '=== ImageDownloadService.downloadMultipleImagesToGallery 시작 ===');
    debugPrint('이미지 URL 개수: ${imageUrls.length}');
    debugPrint('최대 동시 다운로드: $maxConcurrent');

    if (imageUrls.isEmpty) {
      debugPrint('에러: 이미지 URL 리스트가 비어있음');
      return {
        'status': 'error',
        'message': 'Image URLs list is empty',
        'total': 0,
        'success': 0,
        'failed': 0,
        'results': <Map<String, dynamic>>[]
      };
    }

    // 권한 확인
    debugPrint('=== 서비스 레벨 권한 확인 ===');
    if (!await _requestPermissions()) {
      debugPrint('서비스 레벨 권한 확인 실패');
      return {
        'status': 'error',
        'message': 'Permission denied',
        'total': imageUrls.length,
        'success': 0,
        'failed': imageUrls.length,
        'results': imageUrls
            .map((url) =>
                {'url': url, 'status': 'error', 'message': 'Permission denied'})
            .toList()
      };
    }
    debugPrint('서비스 레벨 권한 확인 성공');

    final List<Map<String, dynamic>> results = [];
    int successCount = 0;
    int failedCount = 0;

    // 배치 단위로 다운로드 (동시 다운로드 제한)
    debugPrint('=== 배치 다운로드 시작 ===');
    for (int i = 0; i < imageUrls.length; i += maxConcurrent) {
      final batch = imageUrls.skip(i).take(maxConcurrent).toList();
      debugPrint('배치 ${(i ~/ maxConcurrent) + 1}: ${batch.length}개 이미지 처리');
      for (int j = 0; j < batch.length; j++) {
        debugPrint('  [${i + j + 1}/${imageUrls.length}]: ${batch[j]}');
      }

      // 각 배치 내에서 병렬 다운로드
      debugPrint('배치 병렬 다운로드 시작...');
      final batchResults = await Future.wait(
        batch.map((url) => _downloadSingleImageWithResult(url)),
      );
      debugPrint('배치 다운로드 완료');

      results.addAll(batchResults);

      // 성공/실패 카운트 업데이트
      for (final result in batchResults) {
        if (result['status'] == 'success') {
          successCount++;
          debugPrint('성공: ${result['url']}');
        } else {
          failedCount++;
          debugPrint('실패: ${result['url']} - ${result['message']}');
        }
      }

      // 다음 배치 전 잠시 대기 (마지막 배치가 아닌 경우)
      if (i + maxConcurrent < imageUrls.length) {
        debugPrint('다음 배치 전 ${delayBetweenDownloads.inMilliseconds}ms 대기...');
        await Future.delayed(delayBetweenDownloads);
      }
    }

    final finalResult = {
      'status': successCount > 0 ? 'success' : 'error',
      'message': '$successCount개 성공, $failedCount개 실패',
      'total': imageUrls.length,
      'success': successCount,
      'failed': failedCount,
      'results': results
    };

    debugPrint('=== 최종 결과 ===');
    debugPrint('총 ${imageUrls.length}개 중 $successCount개 성공, $failedCount개 실패');
    debugPrint(
        '=== ImageDownloadService.downloadMultipleImagesToGallery 완료 ===');

    return finalResult;
  }

  /// 단일 이미지 다운로드 with 상세 결과 반환
  static Future<Map<String, dynamic>> _downloadSingleImageWithResult(
      String imageUrl) async {
    debugPrint('--- 단일 이미지 다운로드 시작: $imageUrl');
    try {
      debugPrint('이미지 데이터 다운로드 중...');
      final Uint8List? imageBytes = await _downloadImage(imageUrl);
      if (imageBytes == null) {
        debugPrint('이미지 다운로드 실패: $imageUrl');
        return {
          'url': imageUrl,
          'status': 'error',
          'message': 'Failed to download image'
        };
      }
      debugPrint('이미지 다운로드 성공: ${imageBytes.length} bytes');

      debugPrint('갤러리에 저장 중...');
      final bool saved = await _saveImageToGallery(imageBytes);
      if (saved) {
        debugPrint('갤러리 저장 성공: $imageUrl');
        return {
          'url': imageUrl,
          'status': 'success',
          'message': 'Image saved to gallery'
        };
      } else {
        debugPrint('갤러리 저장 실패: $imageUrl');
        return {
          'url': imageUrl,
          'status': 'error',
          'message': 'Failed to save image to gallery'
        };
      }
    } catch (e) {
      debugPrint('단일 이미지 처리 중 예외 발생: $imageUrl - $e');
      return {
        'url': imageUrl,
        'status': 'error',
        'message': 'Error: ${e.toString()}'
      };
    }
  }

  /// 저장소 접근 권한 요청
  static Future<Map<String, dynamic>> requestPermissionsWithStatus() async {
    debugPrint('=== requestPermissionsWithStatus 시작 ===');

    try {
      // gal 패키지의 권한 확인
      debugPrint('현재 권한 상태 확인 중...');
      bool hasAccess = await Gal.hasAccess();

      if (hasAccess) {
        debugPrint('권한이 이미 허용됨');
        return {
          'granted': true,
          'status': 'granted',
          'message': '권한이 이미 허용되었습니다.'
        };
      }

      // 권한 요청
      debugPrint('권한 요청 중...');
      bool granted = await Gal.requestAccess();
      debugPrint('권한 요청 결과: $granted');

      if (granted) {
        debugPrint('권한 허용됨');
        return {
          'granted': true,
          'status': 'granted',
          'message': '권한이 허용되었습니다.'
        };
      } else {
        debugPrint('권한 거부됨');
        return {
          'granted': false,
          'status': 'denied',
          'message': '권한이 거부되었습니다.',
          'canRetry': true
        };
      }
    } catch (e) {
      debugPrint('권한 처리 중 예외 발생: $e');

      // GalException 처리
      if (e.toString().contains('accessDenied')) {
        debugPrint('접근 권한 거부됨');
        return {
          'granted': false,
          'status': 'permanently_denied',
          'message': '사진 라이브러리 접근 권한이 거부되었습니다. 설정에서 권한을 허용해주세요.',
          'requiresSettings': true
        };
      }

      return {
        'granted': false,
        'status': 'error',
        'message': '권한 확인 중 오류가 발생했습니다: ${e.toString()}'
      };
    }
  }

  /// 저장소 접근 권한 요청 (기존 호환성 유지)
  static Future<bool> _requestPermissions() async {
    debugPrint('=== _requestPermissions 호출 ===');
    final result = await requestPermissionsWithStatus();
    debugPrint('권한 요청 최종 결과: ${result['granted']}');
    return result['granted'] == true;
  }

  /// 이미지 URL에서 이미지 데이터 다운로드
  static Future<Uint8List?> _downloadImage(String imageUrl) async {
    debugPrint('HTTP GET 요청: $imageUrl');
    try {
      final Response<List<int>> response = await _dio.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      debugPrint('HTTP 응답: ${response.statusCode}');
      if (response.statusCode == 200 && response.data != null) {
        debugPrint('이미지 데이터 수신 성공: ${response.data!.length} bytes');
        return Uint8List.fromList(response.data!);
      }
      debugPrint('HTTP 응답 실패 또는 데이터 없음');
      return null;
    } catch (e) {
      debugPrint('HTTP 요청 중 예외 발생: $e');
      return null;
    }
  }

  /// 이미지를 갤러리에 저장
  static Future<bool> _saveImageToGallery(Uint8List imageBytes) async {
    final fileName = "PrayU_${DateTime.now().millisecondsSinceEpoch}";
    debugPrint('갤러리 저장 시도: $fileName.jpg (${imageBytes.length} bytes)');

    try {
      // gal 패키지 사용
      await Gal.putImageBytes(imageBytes, name: fileName);
      debugPrint('갤러리 저장 성공: $fileName');
      return true;
    } catch (e) {
      debugPrint('갤러리 저장 중 예외 발생: $e');
      return false;
    }
  }
}
