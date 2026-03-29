// Copyright 2026 The Project Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

module top (
    input clk,             // Pin 52 (27MHz)
    
    // MAX98357A DAC output
    output dac_bclk,       // Pin 26
    output dac_lrclk,      // Pin 27
    output dac_dat,        // Pin 25
    
    // INMP441 Microphone input
    output mic_sck,        // Pin 29
    output mic_ws,         // Pin 30
    input  mic_sd,         // Pin 28

    // User Interface
    input  btn_s1,         // Pin 3 (S1)
    input  btn_s2,         // Pin 4 (S2)
    input  btn_vol,        // External Button (Pin 77, Pull-up)
    output led_4,          // Pin 14 (Equalizer Status)
    output led_5,          // Pin 15 (Compressor Status)
    output [2:0] led_vol   // Pins 10, 11, 13 (Volume Bar)
);

    wire bclk;
    wire lrclk;
    wire [31:0] audio_l;
    wire [31:0] audio_r;
    wire ready;

    wire [31:0] audio_out_final;

    // Clock Generator (Sets Sample Rate to ~46.88 kHz)
    i2s_clock clk_gen (
        .clk(clk),
        .bclk(bclk),
        .lrclk(lrclk)
    );

    // I2S Receiver (Microphone)
    i2s_rx mic_rx (
        .bclk(bclk),
        .lrclk(lrclk),
        .sd(mic_sd),
        .data_l(audio_l),
        .data_r(audio_r),
        .ready(ready)
    );

    // --- Button Debouncing and Toggle Logic ---
    reg [19:0] d_cnt1 = 0, d_cnt2 = 0;
    reg btn1_r = 1, btn2_r = 1;
    reg btn1_p = 1, btn2_p = 1;
    reg comp_on = 1, eq_on = 1; // Default BOTH ON

    always @(posedge clk) begin
        // Debounce btn_s1 (Compressor)
        if (btn_s1 != btn1_r) begin
            if (d_cnt1 == 20'd1000000) btn1_r <= btn_s1;
            else d_cnt1 <= d_cnt1 + 1;
        end else d_cnt1 <= 0;

        // Debounce btn_s2 (Equalizer)
        if (btn_s2 != btn2_r) begin
            if (d_cnt2 == 20'd1000000) btn2_r <= btn_s2;
            else d_cnt2 <= d_cnt2 + 1;
        end else d_cnt2 <= 0;

        // Edge detection and toggles
        btn1_p <= btn1_r;
        if (btn1_p && !btn1_r) comp_on <= !comp_on;

        btn2_p <= btn2_r;
        if (btn2_p && !btn2_r) eq_on <= !eq_on;
    end

    // LED Indicators (Active Low on Tang Nano)
    assign led_4 = !eq_on;   // LED 4: Equalizer status
    assign led_5 = !comp_on; // LED 5: Compressor status

    // --- DSP Pipeline ---

    wire signed [23:0] audio_pre;
    wire signed [23:0] compressed_audio;
    wire signed [23:0] eq_audio;
    wire signed [23:0] limited_audio;
    wire signed [23:0] vol_audio;
    wire comp_ready, eq_ready, lim_ready, vol_ready;

    wire signed [23:0] audio_raw = audio_l[31:8];
    wire signed [27:0] pre_gain_val = $signed(audio_raw) <<< 4;
    assign audio_pre = (pre_gain_val[27] ^ pre_gain_val[23]) ? 
                       (pre_gain_val[27] ? 24'sh800000 : 24'sh7FFFFF) : 
                       pre_gain_val[23:0];

    // 1. Compressor Instance (Speech compression)
    compressor_core compressor (
        .clk(clk),
        .rst_n(1'b1), 
        .ce(ready),
        .sample_in(audio_pre),
        .sample_out(compressed_audio),
        .ready(comp_ready)
    );

    // Bypass mux for Compressor
    wire signed [23:0] mux_comp_audio = comp_on ? compressed_audio : audio_pre;
    wire mux_comp_ready = comp_on ? comp_ready : ready;

    // 2. Equalizer Instance (Speech optimization)
    equalizer_core equalizer (
        .clk(clk),
        .rst_n(1'b1),
        .ce(mux_comp_ready),
        .sample_in(mux_comp_audio),
        .sample_out(eq_audio),
        .ready(eq_ready)
    );

    // 3. Selection Mux and Limiter
    // Pass either EQ output or Compressor output to Limiter
    wire signed [23:0] mux_audio = eq_on ? eq_audio : compressed_audio;
    wire mux_ready = eq_on ? eq_ready : comp_ready;

    limiter_core limiter (
        .clk(clk),
        .rst_n(1'b1), 
        .ce(mux_ready),
        .sample_in(mux_audio),
        .sample_out(limited_audio),
        .ready(lim_ready)
    );

    // 4. Volume Control Integrated at the end of the chain
    wire [2:0] vol_led_bus;
    volume_control volume (
        .clk(clk),
        .rst_n(1'b1),
        .ready_in(lim_ready),
        .btn_vol(btn_vol),
        .audio_in(limited_audio),
        .audio_out(vol_audio),
        .led_vol(vol_led_bus),
        .ready_out(vol_ready)
    );

    // Map volume LEDs (invert for Tang Nano 9k Active-Low LEDs)
    assign led_vol = ~vol_led_bus;

    // Map 24-bit processed audio back to 32-bit slot for DAC
    assign audio_out_final = {vol_audio, 8'h00};
 

    // I2S Transmitter (DAC)
    // Forward the attenuated channel to both DAC channels
    i2s_tx dac_tx (
        .bclk(bclk),
        .lrclk(lrclk),
        .data_l(audio_out_final),
        .data_r(audio_out_final), 
        .sdata(dac_dat)
    );

    // Assign common clocks to both devices
    assign dac_bclk = bclk;
    assign dac_lrclk = lrclk;
    assign mic_sck = bclk;
    assign mic_ws = lrclk;

endmodule
