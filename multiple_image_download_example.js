// PrayU 앱 다중 이미지 다운로드 기능 사용 예제

/**
 * 단일 이미지 다운로드 (기존 기능)
 * @param {string} imageUrl - 다운로드할 이미지 URL
 * @param {function} onSuccess - 성공 콜백 (선택적)
 * @param {function} onError - 실패 콜백 (선택적)
 */
function downloadSingleImage(imageUrl, onSuccess, onError) {
  if (!window.flutter_inappwebview) {
    const message = "이 기능은 PrayU 앱에서만 사용할 수 있습니다.";
    if (onError) onError(message);
    return;
  }

  window.flutter_inappwebview
    .callHandler("downloadImage", imageUrl)
    .then((result) => {
      if (result.status === "success") {
        if (onSuccess) onSuccess(result.message);
      } else {
        if (onError) onError(result.message);
      }
    })
    .catch((error) => {
      if (onError) onError("다운로드 중 오류가 발생했습니다: " + error);
    });
}

/**
 * 여러 이미지 동시 다운로드 (새로운 기능)
 * @param {string[]} imageUrls - 다운로드할 이미지 URL 배열
 * @param {object} options - 옵션 설정
 * @param {number} options.maxConcurrent - 동시 다운로드 수 (기본값: 3, 최대: 10)
 * @param {function} options.onProgress - 진행상황 콜백 (선택적)
 * @param {function} options.onComplete - 완료 콜백 (선택적)
 * @param {function} options.onError - 에러 콜백 (선택적)
 */
function downloadMultipleImages(imageUrls, options = {}) {
  if (!window.flutter_inappwebview) {
    const message = "이 기능은 PrayU 앱에서만 사용할 수 있습니다.";
    if (options.onError) options.onError(message);
    return;
  }

  if (!Array.isArray(imageUrls) || imageUrls.length === 0) {
    const message = "이미지 URL 배열이 유효하지 않습니다.";
    if (options.onError) options.onError(message);
    return;
  }

  const maxConcurrent = Math.min(Math.max(options.maxConcurrent || 3, 1), 10);

  console.log(
    `${imageUrls.length}개 이미지 다운로드 시작 (동시 다운로드: ${maxConcurrent}개)`
  );

  window.flutter_inappwebview
    .callHandler("downloadMultipleImages", imageUrls, maxConcurrent)
    .then((result) => {
      console.log("다중 이미지 다운로드 결과:", result);

      if (options.onProgress) {
        options.onProgress({
          total: result.total,
          success: result.success,
          failed: result.failed,
          percentage: Math.round(
            ((result.success + result.failed) / result.total) * 100
          ),
        });
      }

      if (options.onComplete) {
        options.onComplete(result);
      }
    })
    .catch((error) => {
      console.error("다중 이미지 다운로드 에러:", error);
      if (options.onError) {
        options.onError("다운로드 중 오류가 발생했습니다: " + error);
      }
    });
}

/**
 * 이미지 요소들로부터 URL을 추출하여 다운로드
 * @param {string} selector - CSS 선택자
 * @param {object} options - downloadMultipleImages와 동일한 옵션
 */
function downloadImagesFromSelector(selector, options = {}) {
  const imageElements = document.querySelectorAll(selector);
  const imageUrls = Array.from(imageElements)
    .map((img) => img.src || img.dataset.src)
    .filter((url) => url && url.startsWith("http"));

  if (imageUrls.length === 0) {
    const message = `선택자 "${selector}"로 이미지를 찾을 수 없습니다.`;
    if (options.onError) options.onError(message);
    return;
  }

  console.log(`${imageUrls.length}개 이미지 URL 추출됨`);
  downloadMultipleImages(imageUrls, options);
}

// 사용 예제들

// 1. 기본 다중 이미지 다운로드
function example1() {
  const imageUrls = [
    "https://picsum.photos/400/300?random=1",
    "https://picsum.photos/400/300?random=2",
    "https://picsum.photos/400/300?random=3",
    "https://picsum.photos/400/300?random=4",
    "https://picsum.photos/400/300?random=5",
  ];

  downloadMultipleImages(imageUrls, {
    maxConcurrent: 3,
    onComplete: (result) => {
      alert(
        `다운로드 완료!\n성공: ${result.success}개\n실패: ${result.failed}개`
      );
    },
    onError: (error) => {
      alert("에러: " + error);
    },
  });
}

// 2. 진행상황을 보여주는 다운로드
function example2() {
  const imageUrls = [
    "https://picsum.photos/600/400?random=11",
    "https://picsum.photos/600/400?random=12",
    "https://picsum.photos/600/400?random=13",
  ];

  // 진행률 표시용 요소 생성 (선택적)
  const progressDiv = document.createElement("div");
  progressDiv.id = "download-progress";
  progressDiv.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        background: rgba(0,0,0,0.8);
        color: white;
        padding: 10px;
        border-radius: 5px;
        z-index: 9999;
    `;
  document.body.appendChild(progressDiv);

  downloadMultipleImages(imageUrls, {
    maxConcurrent: 2,
    onProgress: (progress) => {
      progressDiv.innerHTML = `
                다운로드 진행중...<br>
                ${progress.success + progress.failed}/${progress.total} (${
        progress.percentage
      }%)<br>
                성공: ${progress.success}, 실패: ${progress.failed}
            `;
    },
    onComplete: (result) => {
      progressDiv.innerHTML = `
                다운로드 완료!<br>
                성공: ${result.success}개<br>
                실패: ${result.failed}개
            `;

      setTimeout(() => {
        document.body.removeChild(progressDiv);
      }, 3000);
    },
    onError: (error) => {
      progressDiv.innerHTML = "에러: " + error;
      setTimeout(() => {
        document.body.removeChild(progressDiv);
      }, 3000);
    },
  });
}

// 3. 페이지의 모든 이미지 다운로드
function downloadAllImagesOnPage() {
  downloadImagesFromSelector("img", {
    maxConcurrent: 3,
    onComplete: (result) => {
      console.log("페이지 이미지 다운로드 완료:", result);
      alert(
        `페이지의 이미지 다운로드 완료!\n성공: ${result.success}개\n실패: ${result.failed}개`
      );
    },
    onError: (error) => {
      alert("에러: " + error);
    },
  });
}

// 4. 특정 클래스의 이미지들만 다운로드
function downloadGalleryImages() {
  downloadImagesFromSelector(".gallery-image", {
    maxConcurrent: 4,
    onComplete: (result) => {
      alert(
        `갤러리 이미지 다운로드 완료!\n성공: ${result.success}개\n실패: ${result.failed}개`
      );
    },
  });
}

// 5. 버튼 이벤트 설정 함수
function setupDownloadButtons() {
  // 단일 이미지 다운로드 버튼
  const singleBtn = document.getElementById("download-single");
  if (singleBtn) {
    singleBtn.addEventListener("click", () => {
      const imageUrl = "https://picsum.photos/500/500?random=99";
      downloadSingleImage(
        imageUrl,
        (message) => alert("성공: " + message),
        (error) => alert("실패: " + error)
      );
    });
  }

  // 다중 이미지 다운로드 버튼
  const multipleBtn = document.getElementById("download-multiple");
  if (multipleBtn) {
    multipleBtn.addEventListener("click", example1);
  }

  // 진행률 표시 다운로드 버튼
  const progressBtn = document.getElementById("download-with-progress");
  if (progressBtn) {
    progressBtn.addEventListener("click", example2);
  }

  // 페이지 전체 이미지 다운로드 버튼
  const allBtn = document.getElementById("download-all");
  if (allBtn) {
    allBtn.addEventListener("click", downloadAllImagesOnPage);
  }
}

// Flutter 앱에서 보내는 메시지 수신
window.addEventListener("message", function (event) {
  const data = event.data;

  switch (data.type) {
    case "IMAGE_DOWNLOAD_SUCCESS":
      console.log("단일 이미지 다운로드 성공:", data.message);
      break;

    case "IMAGE_DOWNLOAD_ERROR":
      console.log("단일 이미지 다운로드 실패:", data.message);
      break;

    case "MULTIPLE_IMAGE_DOWNLOAD_RESULT":
      console.log("다중 이미지 다운로드 결과:", data.result);
      break;

    case "MULTIPLE_IMAGE_DOWNLOAD_ERROR":
      console.log("다중 이미지 다운로드 에러:", data.result);
      break;
  }
});

// 페이지 로드 완료 후 버튼 이벤트 설정
document.addEventListener("DOMContentLoaded", function () {
  setupDownloadButtons();
  console.log("PrayU 다중 이미지 다운로드 기능이 준비되었습니다.");
});

/* HTML 예제:
<!DOCTYPE html>
<html>
<head>
    <title>PrayU 다중 이미지 다운로드 테스트</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; padding: 20px; }
        button { margin: 10px; padding: 10px 20px; font-size: 16px; }
        .gallery-image { width: 200px; height: 150px; margin: 5px; }
        .test-section { margin: 20px 0; padding: 15px; border: 1px solid #ccc; }
    </style>
</head>
<body>
    <h1>PrayU 앱 이미지 다운로드 테스트</h1>
    
    <div class="test-section">
        <h2>기본 기능 테스트</h2>
        <button id="download-single">단일 이미지 다운로드</button>
        <button id="download-multiple">다중 이미지 다운로드 (5개)</button>
        <button id="download-with-progress">진행률 표시 다운로드</button>
    </div>
    
    <div class="test-section">
        <h2>페이지 이미지 다운로드</h2>
        <button id="download-all">페이지 전체 이미지 다운로드</button>
        
        <h3>테스트 이미지들</h3>
        <img class="gallery-image" src="https://picsum.photos/200/150?random=1" alt="테스트1">
        <img class="gallery-image" src="https://picsum.photos/200/150?random=2" alt="테스트2">
        <img class="gallery-image" src="https://picsum.photos/200/150?random=3" alt="테스트3">
    </div>
    
    <script src="multiple_image_download_example.js"></script>
</body>
</html>
*/
