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
 * Limiter Core - Digital Audio Limiter
 * 
 * This module coordinates the peak envelope detection and gain application.
 * It uses a 32-sample lookahead FIFO to effectively pre-empt peaks.
 * 
 * Latency Breakdown:
 * 1. Envelope Detector: 1 sample strobe (ce)
 * 2. Gain Computer ROM: 1 system clock
 * 3. Multiplier Pipeline: 2 system clocks
 */
module limiter_core (
    input  wire clk,
    input  wire rst_n,
    input  wire ce,                 // New sample strobe (sync with BCLK/LRCLK)
    input  wire signed [23:0] sample_in,
    output reg  signed [23:0] sample_out,
    output reg  ready               // Output data valid
);

    // Parameters (Can be moved to inputs for real-time control)
    // alpha = (1 - e^(-1/(tau*fs))) * 2^16
    // fs = 48kHz
    // attack = 1ms -> alpha_attack approx 20000 (16-bit fraction)
    // release = 100ms -> alpha_release approx 200
    wire [15:0] alpha_attack  = 16'd20000;
    wire [15:0] alpha_release = 16'd150;

    // 1. Lookahead Buffer
    // Circular buffer to hold 32 samples (approx 0.67ms @ 48kHz)
    reg signed [23:0] lookahead_fifo [0:31];
    reg [4:0] write_ptr = 0;
    reg [4:0] read_ptr = 0;

    always @(posedge clk) begin
        if (ce) begin
            lookahead_fifo[write_ptr] <= sample_in;
            write_ptr <= write_ptr + 1'b1;
            // The read pointer is technically just behind the write pointer 
            // in a delay line.
            read_ptr <= write_ptr + 1'b1; 
        end
    end
    wire signed [23:0] delayed_sample = lookahead_fifo[read_ptr];

    // 2. Peak Envelope Detection
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

    // 3. Gain Calculation
    wire [24:0] gain; // 1.24 fixed point
    gain_computer gc (
        .clk(clk),
        .envelope_in(envelope),
        .gain_out(gain)
    );

    // 4. Apply Gain (Pipelined Multiplier)
    // sample_out = sample * gain
    // Latency handling:
    // ce pulse -> envelope updated at next clk
    // envelope -> gain updated at next clk
    // We need to buffer the delayed_sample to match this 2-clock system latency.
    
    reg signed [23:0] delayed_sample_q1, delayed_sample_q2;
    reg ce_q1, ce_q2, ce_q3;

    reg signed [48:0] p;
    always @(posedge clk) begin
        // Store the sample from FIFO and sync the strobe
        if (ce) begin
            delayed_sample_q1 <= delayed_sample;
            ce_q1 <= 1'b1;
        end else begin
            ce_q1 <= 1'b0;
        end

        // Wait for gain computer (1 cycle latency)
        delayed_sample_q2 <= delayed_sample_q1;
        ce_q2 <= ce_q1;

        // Perform multiplication
        if (ce_q2) begin
            // 24-bit signed * 25-bit unsigned (gain)
            // We use a temporary 49-bit product
            // product = delayed_sample * gain
            // Bits 47:24 contain the 24-bit signed result.
            // product[48:47] are sign extension.
            // product[23:0] are fractional remainder.
            p = $signed(delayed_sample_q2) * $signed({1'b0, gain});
            sample_out <= p[47:24];
            ce_q3 <= 1'b1;
        end else begin
            ce_q3 <= 1'b0;
        end
        
        ready <= ce_q3;
    end

endmodule
