#import "NSExceptionCatcher.h"

BOOL catchException(void(NS_NOESCAPE ^tryBlock)(void)) {
    @try {
        tryBlock();
        return YES; // Khối lệnh chạy trơn tru, không có ngoại lệ
    }
    @catch (NSException *exception) {
        // Bắt trọn ngoại lệ Apple (ví dụ thiếu Entitlement), ngăn chặn sập app và trả về NO an toàn
        return NO;
    }
}
