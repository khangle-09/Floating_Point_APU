# THIẾT KẾ ALU SỐ CHẤM ĐỘNG 32-BIT CHUẨN IEEE-754 BẰNG VERILOG

> Tài liệu này bám theo mục lục bạn gửi, đã thay nội dung "chuẩn I2C" ở Chương 2 bằng "chuẩn IEEE-754" cho đúng đề tài. Bạn điền thêm số liệu/kết quả mô phỏng của nhóm vào các chỗ `[...]`.

---

# CHƯƠNG 1: TỔNG QUAN

## 1.1 ĐẶT VẤN ĐỀ
Các phép tính số thực (chấm động) là nền tảng của xử lý tín hiệu, đồ họa, AI, mô phỏng khoa học... Trên phần cứng, chúng được thực hiện bởi khối FPU/FP-ALU. Việc tự thiết kế một FP-ALU giúp hiểu sâu cách máy tính biểu diễn và tính toán số thực, đồng thời rèn kỹ năng thiết kế số bằng Verilog và kiểm chứng trên FPGA.

## 1.2 MỤC TIÊU
Thiết kế và mô phỏng một ALU số chấm động 32-bit theo chuẩn IEEE-754 single precision, hỗ trợ 4 phép toán: cộng, trừ, nhân, chia; có xử lý các trường hợp đặc biệt (0, ±∞, NaN) và làm tròn round-to-nearest-even.

## 1.3 NỘI DUNG NGHIÊN CỨU
- Chuẩn biểu diễn số IEEE-754 single precision.
- Giải thuật cộng/trừ, nhân, chia số chấm động.
- Kỹ thuật chuẩn hóa (normalize) và làm tròn (rounding, guard/round/sticky).
- Hiện thực bằng Verilog, mô phỏng bằng ModelSim, kiểm chứng trên kit FPGA.

## 1.4 BỐ CỤC
Báo cáo gồm 6 chương: Tổng quan; Cơ sở lý thuyết; Thiết kế; Đánh giá bằng testbench; Đánh giá trên FPGA; Kết luận.

## 1.5 GIỚI HẠN
- Chỉ hỗ trợ single precision (32-bit).
- Chế độ làm tròn: round-to-nearest-even.
- Số denormal (subnormal) được xử lý đơn giản (flush-to-zero khi underflow) — xem hướng phát triển.
- Khối chia hiện thực dạng tổ hợp (tốn tài nguyên); bản tối ưu tài nguyên cho FPGA nên dùng bộ chia tuần tự.

---

# CHƯƠNG 2: CƠ SỞ LÝ THUYẾT

## 2.1 GIỚI THIỆU VỀ CHUẨN IEEE-754
IEEE-754 single precision biểu diễn số thực bằng 32 bit, chia làm 3 trường:

| Trường | Số bit | Vị trí |
|---|---|---|
| Sign (dấu) `S` | 1 | bit 31 |
| Exponent (mũ) `E` | 8 | bit 30–23 |
| Fraction/Mantissa (phần lẻ) `F` | 23 | bit 22–0 |

Giá trị (với số bình thường, `1 ≤ E ≤ 254`):

  value = (−1)^S × 1.F × 2^(E − 127)

- `127` là **bias** của mũ.
- `1.F` có **bit ẩn (hidden bit)** bằng 1 ở trước dấu chấm → mantissa thực chất có 24 bit (`1` + 23 bit lẻ).

## 2.2 ĐẶC ĐIỂM VÀ NGUYÊN LÝ HOẠT ĐỘNG

### Các giá trị đặc biệt
| E | F | Ý nghĩa |
|---|---|---|
| 0 | 0 | Số 0 (±0 theo dấu S) |
| 0 | ≠ 0 | Số denormal (subnormal) |
| 1…254 | bất kỳ | Số bình thường (normalized) |
| 255 | 0 | ±∞ (Infinity) |
| 255 | ≠ 0 | NaN (Not a Number) |

### Làm tròn round-to-nearest-even (RNE)
Khi cắt bớt mantissa, ta giữ thêm 3 bit phụ:
- **Guard (G)**: bit ngay sau LSB được giữ.
- **Round (R)**: bit kế tiếp.
- **Sticky (S)**: OR của tất cả các bit còn lại phía dưới.

Quy tắc làm tròn lên: `round_up = G AND (R OR S OR LSB)`
(LSB là bit cuối của mantissa được giữ — bảo đảm "làm tròn về số chẵn" khi rơi đúng điểm giữa).

---

# CHƯƠNG 3. THIẾT KẾ

## 3.1 SƠ ĐỒ KHỐI THIẾT KẾ
Khối `fp_alu` nhận 2 toán hạng `a`, `b` (32-bit) và mã phép toán `op` (3-bit). Bên trong gồm 4 khối con tính song song (`fp_add_sub` cho cả + và −, `fp_mul`, `fp_div`); một bộ MUX chọn kết quả theo `op`. Đầu ra kèm cờ trạng thái `nan/inf/zero`.

```
        a[31:0] ─┬─────────────┬─────────────┬─────────────┐
        b[31:0] ─┤             │             │             │
                 ▼             ▼             ▼             ▼
          ┌────────────┐ ┌────────────┐ ┌────────┐ ┌────────┐
          │ fp_add_sub │ │ fp_add_sub │ │ fp_mul │ │ fp_div │
          │  (sub=0)   │ │  (sub=1)   │ │        │ │        │
          └─────┬──────┘ └─────┬──────┘ └───┬────┘ └───┬────┘
                │ r_add        │ r_sub      │ r_mul    │ r_div
                └──────┬───────┴──────┬─────┴─────┬────┘
                       ▼              ▼           ▼
                     ┌──────────────  MUX  ──────────────┐  ◄── op[2:0]
                     └─────────────────┬─────────────────┘
                                       ▼
                              result[31:0] + (nan/inf/zero)
```

## 3.2 MÔ TẢ THANH GHI / TÍN HIỆU

### 3.2.1 Tổng quát
ALU là khối tổ hợp nên không có thanh ghi trạng thái; các "thanh ghi" dưới đây là cổng vào/ra (port) và tín hiệu nội bộ chính.

### 3.2.2 Thanh ghi (port) giao tiếp
| Tín hiệu | Hướng | Bit | Mô tả |
|---|---|---|---|
| `a` | in | 32 | Toán hạng 1 (IEEE-754) |
| `b` | in | 32 | Toán hạng 2 (IEEE-754) |
| `op` | in | 3 | 000=ADD, 001=SUB, 010=MUL, 011=DIV |
| `result` | out | 32 | Kết quả (IEEE-754) |
| `nan/inf/zero` | out | 1 | Cờ trạng thái |

### 3.2.3 Tín hiệu nội bộ tiêu biểu (khối cộng/trừ)
| Tín hiệu | Mô tả |
|---|---|
| `sig_a, sig_b` | Mantissa 24-bit (gồm hidden bit) |
| `ediff` | Chênh lệch mũ giữa 2 toán hạng |
| `sml_sh` | Mantissa nhỏ sau khi dịch phải căn chỉnh |
| `sum` | Kết quả cộng/trừ mantissa (28-bit) |
| `g, r, st` | Guard / Round / Sticky |

## 3.3 THIẾT KẾ CHI TIẾT

### 3.3.1 Khối cộng/trừ (`fp_add_sub.v`)
Các bước: Unpack → So sánh & căn chỉnh mũ (dịch phải mantissa nhỏ) → Cộng/trừ mantissa → Chuẩn hóa → Làm tròn → Đóng gói. Cộng/trừ được gộp chung: trừ = cộng với b đã đảo dấu.

### 3.3.2 Khối nhân (`fp_mul.v`)
XOR dấu → cộng 2 mũ rồi trừ bias → nhân 2 mantissa (24×24=48-bit) → chuẩn hóa (tích nằm trong [2^46, 2^48) nên chỉ chỉnh tối đa 1 bit) → làm tròn → đóng gói.

### 3.3.3 Khối chia (`fp_div.v`)
XOR dấu → trừ 2 mũ rồi cộng bias → chia mantissa bằng restoring division (q = ⌊sig_a·2^26 / sig_b⌋) → chuẩn hóa (tỉ số trong (0.5, 2) → chỉnh tối đa 1 bit) → làm tròn → đóng gói.

## 3.4 THIẾT KẾ GIẢI THUẬT

### 3.4.1 Giải thuật cho khối cộng/trừ
1. Tách S/E/F của a, b; gắn hidden bit thành mantissa 24-bit.
2. Xác định toán hạng lớn hơn (theo E, rồi theo mantissa).
3. `ediff = E_big − E_small`; dịch phải mantissa nhỏ `ediff` bit, gom bit rơi vào sticky.
4. Cùng dấu → cộng; khác dấu → trừ mantissa.
5. Chuẩn hóa: nếu tràn (carry) dịch phải 1, tăng mũ; nếu có bit 0 dẫn đầu thì dịch trái, giảm mũ.
6. Làm tròn RNE bằng G/R/S.
7. Kiểm tra tràn/underflow, đóng gói; xử lý 0/∞/NaN.

### 3.4.2 Giải thuật cho khối nhân và chia
Xem 3.3.2 và 3.3.3 (giải thuật mô tả ngay trong mã nguồn).

---

# CHƯƠNG 4. ĐÁNH GIÁ QUA TESTBENCH

## 4.1 Mô hình testbench tổng quát
File `tb_fp_alu.v` cấp các vector `a`, `b`, `op` cho DUT (`fp_alu`), so kết quả `result` với giá trị kỳ vọng (đã tính sẵn theo IEEE-754) và đếm số lỗi.

## 4.2 Mô tả các testcase
| # | Phép tính | a | b | Kỳ vọng |
|---|---|---|---|---|
| 1 | 1.0 + 1.0 | 3F800000 | 3F800000 | 40000000 (2.0) |
| 2 | 1.0 + 2.0 | 3F800000 | 40000000 | 40400000 (3.0) |
| 3 | 3.0 − 1.0 | 40400000 | 3F800000 | 40000000 (2.0) |
| 4 | −1.5 + 1.5 | BFC00000 | 3FC00000 | 00000000 (0) |
| 5 | 2.0 × 3.0 | 40000000 | 40400000 | 40C00000 (6.0) |
| 6 | 6.0 ÷ 2.0 | 40C00000 | 40000000 | 40400000 (3.0) |
| 7 | 1.0 ÷ 3.0 | 3F800000 | 40400000 | 3EAAAAAB |
| 8 | ∞ + 1 | 7F800000 | 3F800000 | 7F800000 (∞) |
| 9 | 1 ÷ 0 | 3F800000 | 00000000 | 7F800000 (∞) |
| 10 | 0 × ∞ | 00000000 | 7F800000 | 7FC00000 (NaN) |

## 4.3 Kết quả
`[Dán log ModelSim: các dòng PASS/FAIL và dòng tổng kết]`

## 4.4 Nhận xét và đánh giá
`[Nhận xét độ chính xác, các trường hợp biên, sai số làm tròn nếu có]`

---

# CHƯƠNG 5. ĐÁNH GIÁ TRÊN KIT FPGA

## 5.1 Mô tả phần cứng
`[Tên kit, ví dụ DE2/DE10, công cụ tổng hợp Quartus/Vivado; ánh xạ a,b qua switch hoặc nạp sẵn; result hiển thị LED/7-seg]`

## 5.2 Kết quả
`[Tài nguyên LUT/FF, tần số tối đa Fmax, ảnh chụp kết quả trên kit]`

## 5.3 Nhận xét và đánh giá
`[Khối chia tổ hợp chiếm nhiều tài nguyên — đề xuất thay bằng bộ chia tuần tự]`

---

# CHƯƠNG 6. KẾT LUẬN VÀ HƯỚNG PHÁT TRIỂN
- Đã hiện thực FP-ALU 32-bit IEEE-754 với +, −, ×, ÷; mô phỏng đạt yêu cầu.
- Hướng phát triển: hỗ trợ đầy đủ số denormal; thêm các chế độ làm tròn khác; pipeline để tăng tần số; bộ chia tuần tự (FSM) để tiết kiệm tài nguyên; thêm phép so sánh, căn bậc hai (sqrt), FMA.

---

# TÀI LIỆU THAM KHẢO
[1] IEEE Std 754-2019, *IEEE Standard for Floating-Point Arithmetic*.
[2] D. A. Patterson, J. L. Hennessy, *Computer Organization and Design*.
[3] `[Tài liệu Verilog/ModelSim mà nhóm sử dụng]`
