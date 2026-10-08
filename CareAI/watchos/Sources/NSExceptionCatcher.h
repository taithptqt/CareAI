#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Cầu nối bắt Objective-C NSException trong Swift (Objective-C Exception Catcher Bridge).
 *
 * Lý do kỹ thuật:
 * Trên watchOS, API CMFallDetectionManager.isAvailable sẽ quăng ngoại lệ cấp thấp
 * NSInternalInconsistencyException ("Fall Detection entitlement is required for this API")
 * nếu app không có entitlement đặc quyền `com.apple.developer.coremotion.fall-detection`.
 *
 * Khối lệnh do-catch của Swift chỉ bắt được lỗi kiểu Swift.Error chứ KHÔNG THỂ bắt được
 * ngoại lệ NSException của Objective-C, dẫn đến việc ứng dụng bị hệ điều hành crash lập tức
 * (Terminating app due to uncaught exception) trước khi kịp rơi xuống nhánh else dự phòng.
 *
 * Hàm này bọc khối lệnh trong cú pháp @try-@catch của Objective-C để bắt trọn ngoại lệ đó,
 * trả về NO an toàn mà không làm sập ứng dụng.
 */
BOOL catchException(void(NS_NOESCAPE ^tryBlock)(void));

NS_ASSUME_NONNULL_END
