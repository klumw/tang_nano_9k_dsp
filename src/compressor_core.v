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

/*
 * Compressor Core - Digital Audio Compressor for Speech
 * 
 * This module implements a soft compressor with a fixed 4:1 ratio.
 * It reuses the envelope detector and gain computer (LUT).
 * 
 * Formula (4:1): gain = 0.75 * (threshold/env) + 0.25
 * 
 * Time Constants (Speech):
 * - Attack: ~10ms
 * - Release: ~150ms
 */
module compressor_core (
    input  wire clk,
    input  wire rst_n,
    input  wire ce,                 // New sample strobe
    input  wire signed [23:0] sample_in,
    output reg  signed [23:0] sample_out,
    output reg  ready
);

    // Time Constants
    wire [15:0] alpha_attack  = 16'd2000;  // ~10ms
    wire [15:0] alpha_release = 16'd100;   // ~150ms

    // 1. Envelope Detection
    wire [23:0] envelope;
    envelope_detector env_det (
        .clk(clk),
        .rst_n(rst_n),
        .ce(ce),
        .sample_in(sample_in),
        .alpha_attack(alpha_attack),
        .alpha_release(alpha_release),
        .envelope_out(envelope)
    );

    // 2. Base Gain Calculation (Threshold / Envelope)
    wire [24:0] base_gain; // 1.24 fixed point
    gain_computer gc (
        .clk(clk),
        .envelope_in(envelope),
        .gain_out(base_gain)
    );

    // 3. Compress Gain Calculation (4:1 Ratio)
    // gain_comp = 0.75 * base_gain + 0.25
    // In 1.24 domain (Unity = 2^24):
    // p = (base_gain * 3) / 4
    // gain_comp = p + 2^22
    reg [24:0] final_gain;
    reg ce_g;
    
    always @(posedge clk) begin
        ce_g <= ce; // Sync with base_gain latency (1 cycle)
        if (ce_g) begin
            // 25-bit + 2-bit mult -> 27-bit
            // Division by 4 via shift
            final_gain <= (((base_gain * 2'd3) >> 2) + (25'd1 << 22));
        end
    end

    // 4. Apply Gain
    // Multiplier Pipeline
    reg signed [23:0] delayed_sample_q1, delayed_sample_q2, delayed_sample_q3;
    reg ce_q1, ce_q2, ce_q3, ce_q4;

    // FIFO Delay Line (matches internal pipeline latency)
    // env(1) + gain_comp(1) + final_gain(1) + mult(1) = approx 4 cycles
    // We'll use a small shift register for the sample delay
    always @(posedge clk) begin
        if (ce) begin
            delayed_sample_q1 <= sample_in;
            ce_q1 <= 1'b1;
        end else begin
            ce_q1 <= 1'b0;
        end
        
        delayed_sample_q2 <= delayed_sample_q1;
        ce_q2 <= ce_q1;
        
        delayed_sample_q3 <= delayed_sample_q2;
        ce_q3 <= ce_q2;

        if (ce_q3) begin : comp_mult
            reg signed [48:0] p_c;
            p_c = $signed(delayed_sample_q3) * $signed({1'b0, final_gain});
            sample_out <= p_c[47:24];
            ce_q4 <= 1'b1;
        end else begin
            ce_q4 <= 1'b0;
        end
        
        ready <= ce_q4;
    end

endmodule
