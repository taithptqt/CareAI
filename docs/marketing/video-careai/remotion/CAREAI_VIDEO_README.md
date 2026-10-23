# CareAI — bản xem trước Remotion

- Composition chính: `CareAI-Introduction`.
- Thời lượng hiện tại: **42,97 giây** (1.289 frame); 30 fps; khung dọc 1080 × 1920. Nguồn liền mạch 39,5 giây được phát ở tốc độ 0.92 để chậm nhẹ cả hình, phụ đề và tiếng; giữ các khoảng nghỉ ngắn. Các bản trước dài 41,63/41,6/38,63/41,1/46,67/37,9/40,57/55/70 giây.
- Trọng tâm đã sửa: **đồng hồ của người cao tuổi → qua hệ thống CareAI → ứng dụng trên điện thoại người thân**. Cảnh kết nối dùng sơ đồ động có nhãn minh họa, không trình diễn như liên kết Bluetooth trực tiếp từ xa. SOS có thể từ đồng hồ hoặc điện thoại.
- 9 cảnh có timeline riêng trong thư mục Scenes của Studio. Phần ngưỡng ngày/đêm đã được bỏ khỏi bản ngắn.
- 12 ảnh gốc được giữ trong public/screens; bản hiện tại dùng 7 ảnh, minh họa đi làm xa và sơ đồ kết nối đồng hồ/điện thoại, các ảnh khác giữ làm tư liệu.
- Mở đầu mới: “Khi bạn đi làm xa và không thể ở gần cha mẹ, CareAI giúp bạn vơi bớt nỗi lo bằng cách theo dõi sức khỏe và giữ kết nối với người thân mỗi ngày.” Lời được tổng hợp trong một lượt đọc, dài 5,967 giây nguồn. `src/OpeningStory.tsx` minh họa bạn đi làm xa, cha mẹ ở nhà và CareAI kết nối ở giữa; tiêu đề “Đi làm xa nhà / Vẫn gần cha mẹ”. Logo và đường kết nối xuất hiện theo mốc đọc tên CareAI; phụ đề chia theo ý nghĩa.
- Có **một track lời đọc nam tiếng Việt liền mạch**, NamMinh +18%, pitch −3Hz; phát âm tên ứng dụng thành “Ke Ai” để tránh cách đọc pha tiếng Anh. Master hiện tại là public/audio/north-v9/narration-continuous.wav: chỉ thêm nhịp nghỉ trong cảnh theo dõi; tám cảnh khác giữ nguyên byte từ north-v8, gồm mở đầu, cách xưng gọi hệ thống/ứng dụng, cảnh tiếp nhận và slogan đã duyệt. Nhà cung cấp chỉ ghi nhãn vi-VN, không có xác nhận riêng cho giọng miền Bắc; đây là điều chỉnh theo hướng giọng Việt phổ thông/miền Bắc, không phải một preset vùng miền đã được xác minh.
- Phần đầu chỉ đọc “CareAI” một lần trong câu mở. Cảnh kết nối đọc “Hệ thống kết nối đồng hồ của người cao tuổi với ứng dụng trên điện thoại người thân.” Cảnh theo dõi mở bằng “Ứng dụng giúp gia đình…” để tránh lặp thương hiệu; phụ đề đồng bộ với lời mới.
- Khoảng nghỉ giữa các cảnh không quá 88,7 ms ở nguồn, tương đương khoảng 96,4 ms khi phát ở 0.92. Cảnh tiếp nhận có hai câu: “Người thân có thể tiếp nhận sự cố. Gia đình cùng phối hợp hỗ trợ.”, cách nhau 150 ms ở nguồn, tương đương 163 ms khi phát. Giữ khoảng đệm 60 ms ở đầu và 483 ms cho logo cuối của nguồn.
- Phần giới thiệu giải pháp (cảnh theo dõi) giữ **một câu**, thêm ba nhịp nghỉ ngắn theo yêu cầu mới: “Ứng dụng giúp gia đình theo dõi nhịp tim và độ bão hòa oxy trong máu, qua biểu đồ sức khỏe cùng cảnh báo vượt ngưỡng, và nhận định xu hướng kèm báo cáo tuần, để nắm bắt thay đổi và chủ động chăm sóc người thân mỗi ngày.” Một lượt tổng hợp có dấu phẩy tạo ngữ điệu tự nhiên; khoảng lặng sau “máu”, “ngưỡng”, “tuần” được kéo dài thành 320 ms nguồn, tương đương 348 ms trong video, không cắt vào âm tiết. Cảnh dài 9,867 giây nguồn, tương đương khoảng 10,725 giây trong video. Thẻ chức năng và phụ đề theo mốc từ mới, giữ chữ trong lúc nghỉ.
- Phần kết dùng `src/ClosingBrand.tsx`, với slogan **“CareAI – Một kết nối, triệu yêu thương”**, biểu tượng cha mẹ và gia đình nối với logo CareAI. Lời đọc liền mạch, giữ đúng câu này; dấu “–” chỉ dùng trình bày và không được đọc thành từ. Cảnh kết dài 2,267 giây nguồn, tương đương khoảng 2,46 giây khi phát. Theo lựa chọn đã xác nhận của người dùng, chỉ đổi slogan ở phần kết, giữ nguyên đoạn giới thiệu chức năng.
- Có phụ đề tiếng Việt căn theo mốc từ của lời đọc, thông thường chia thành các cụm tối đa 7 từ. Riêng cảnh theo dõi chia cụm theo ý nghĩa; cảnh tiếp nhận giữ trọn mỗi câu trong một trang để tránh cắt vụn ý. Tệp JSON/SRT nằm trong public/.
- Bản hoạt ảnh cập nhật: chữ trượt theo từng dòng, điện thoại bay vào/nghiêng/trôi nhẹ, ảnh chuyển bằng trượt và mờ dần, dải màu quét giữa các cảnh, nền vòng quỹ đạo và đường nhịp tim minh họa, nhãn chức năng xuất hiện theo nhịp, vòng SOS và con trỏ chạm, viền cảnh báo, dấu xác nhận sau tiếp nhận, logo kết bật lên.
- Phóng gần nút SOS, xác nhận gửi, cảnh báo ngã, chỉ đường, nút tiếp nhận và trạng thái đã tiếp nhận. Giảm chữ phụ; giữ tiêu đề chính và phụ đề lời đọc.
- Các đường nhịp tim/vòng/viền là đồ họa trang trí và chú thích thao tác, không biểu diễn mẫu đo mới. Chuyển cảnh quét 0.3 giây; mốc đổi ảnh, thao tác, dấu tiếp nhận và phụ đề bám theo độ dài lời đọc thật.
- Nhạc nền mới `public/audio/music-family-connection.wav`: acoustic/chill-pop tổng hợp gốc, guitar gảy/strum, bass mềm và percussion nhẹ. Nhịp 100 BPM nguồn thành khoảng 92 BPM khi video phát ở 0.92; dài nguồn 39,5 giây, kết hòa âm ở 37,2 giây và fade 1,75 giây. Âm lượng 0.16 dưới giọng đọc. Peak PCM −3,25 dBFS, RMS −18,63 dBFS trước gain; không clipping. Bản piano/pad cũ và SFX được giữ nguyên. Nguồn tạo và số đo nhạc mới ở `public/audio/music-family-connection.md`; các tệp review-mix cũ là lịch sử, master lời đọc hiện tại vẫn là north-v9.
- Bản MP4 đầu tiên đã xuất tại `out/CareAI-Introduction.mp4`; bản này dùng nhạc cũ.
- Bản MP4 dùng nhạc mới đã xuất tại `out/CareAI-Introduction-nhac-moi.mp4`, đồng thời lưu ở `C:/Users/taith/Downloads/CareAI-Introduction-nhac-moi.mp4`. H.264 + AAC, 1080 × 1920, 30 fps, 1.289 frame; thời lượng container 42,987 giây; dung lượng 15.423.935 byte. Đã xác nhận có cả luồng hình và tiếng, âm thanh xuất khác bản cũ, và bản trong Downloads trùng SHA-256 với file xuất.
- Số điện thoại trong ảnh 10 và mã người tiếp nhận trong ảnh 12 được che bằng lớp phủ của video; ảnh gốc không bị sửa.
- Có nhãn giao diện/tình huống minh họa; không suy diễn từ nút SOS sang cảnh báo ngã trong cùng sự kiện.

## Mở lại Studio

Từ thư mục dự án này, chạy `npm run dev -- --no-open`, sau đó mở địa chỉ Studio được lệnh in ra. Khi cổng 3000 có sẵn, composition chính nằm tại `http://localhost:3000/CareAI-Introduction`.

## Xuất lại MP4

Từ thư mục dự án này, chạy `node node_modules/@remotion/cli/remotion-cli.js render CareAI-Introduction out/CareAI-Introduction-nhac-moi.mp4 --codec=h264 --crf=18 --pixel-format=yuv420p --audio-codec=aac`. File MP4 được tạo trong `out/`, có sẵn giọng đọc, nhạc nền và phụ đề. Có thể chép file này sang thư mục khác hoặc điện thoại để chia sẻ.

## Chỉnh sửa

Sửa từng cảnh tại `src/scenes/`, bố cục chung tại `src/SceneFrame.tsx`, timeline tại `src/Composition.tsx` và đăng ký composition tại `src/Root.tsx`.

`generate-scenes.mjs`, `tools/author-70s.mjs` và `tools/author-55s.mjs` thuộc các bản cũ, không chạy lại. `tools/author-continuous.mjs` tạo nguồn liền mạch từ public/audio/voice-manifest.json và continuous-manifest.json trong thư mục audio đang được manifest sử dụng, có giữ Sequence playbackRate0.92. Không chạy lại sau khi chỉnh trực tiếp các cảnh trong Studio vì công cụ sẽ ghi lại các tệp cảnh/timeline.

`tools/generate_continuous_north.py` tái tạo lời đọc liền mạch (cần kết nối dịch vụ TTS); `tools/generate_voice.py` là công cụ chia clip của bản cũ. `tools/generate_family_music.py` tạo bản nhạc nền mới bằng tính toán tại máy. `tools/generate_music.py` tạo nhạc và hiệu ứng của bản cũ. Các thư viện Python phục vụ công cụ được cài riêng trong tools/python-deps và không đưa vào Git.

`tools/patch_acknowledgement_voice.py` ghi nhận lần sửa riêng cảnh tiếp nhận sang north-v3, giữ nguyên tám đoạn PCM khác và rút khoảng nghỉ giữa hai câu về 150 ms.

`tools/patch_monitoring_voice.py` ghi nhận lần mở rộng riêng cảnh theo dõi sang north-v4, giữ nguyên tám đoạn PCM khác, gồm lời tiếp nhận đã sửa. `src/HealthFeatureHighlights.tsx` là đồ họa chú thích ba nhóm chức năng; mốc xuất hiện được lấy từ word timings của cảnh.

`tools/patch_solution_ending_voice.py` ghi nhận lần gộp lời giải pháp thành một câu và tạo lời kết mới sang north-v5, giữ nguyên bảy cảnh còn lại. Các bản north-v3/north-v4 và công cụ sửa của chúng được giữ để tham khảo lịch sử.

`tools/patch_closing_slogan_voice.py` ghi nhận lần đổi riêng slogan phần kết sang north-v6; tám clip và word files khác giữ nguyên byte từ north-v5. Bộ tạo phụ đề bỏ qua dấu gạch ngang đứng riêng khi ánh xạ thời gian phát âm, đồng thời vẫn hiển thị đúng dấu trong câu slogan.

`tools/patch_opening_voice.py` ghi nhận lần đổi riêng mở đầu sang north-v7; tám clip và word files khác giữ nguyên byte từ north-v6. `tools/author-continuous.mjs` lấy mốc từ CareAI để đồng bộ hoạt ảnh kết nối trong `src/OpeningStory.tsx`.

`tools/patch_brand_repetition_voice.py` ghi nhận lần thay “CareAI” bằng “Hệ thống” và “Ứng dụng” trong hai cảnh kết nối và theo dõi sang north-v8; bảy clip và word files khác giữ nguyên byte từ north-v7. Phần mở đầu và slogan vẫn đọc tên thương hiệu.

`tools/patch_monitoring_pauses_voice.py` ghi nhận lần thêm ba nhịp nghỉ trong cảnh theo dõi sang north-v9; tám clip và word files khác giữ nguyên byte từ north-v8. Bộ tạo lời đọc cũng giữ riêng chính sách nghỉ 320 ms của cảnh này.

Phụ đề có bản JSON và SRT trong `public/`. Khi sửa lời hoặc timing từng cảnh, đồng bộ hai bản này nếu muốn dùng chúng riêng.

Lần dựng này xác nhận trực quan trong Remotion Studio. Không chạy build/test/analyze của ứng dụng CareAI.
