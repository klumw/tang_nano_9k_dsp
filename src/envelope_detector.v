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
 * Envelope Detector for Audio Limiter
 * 
 * Implements a simple IIR filter for peak envelope detection:
 * env[n] = env[n-1] + alpha * (abs(sample) - env[n-1])
 * 
 * alpha_attack is used when abs(sample) > env[n-1]
 * alpha_release is used when abs(sample) <= env[n-1]
 * 
 * Fixed-Point:
 * - sample: 24-bit signed
 * - envelope: 24-bit unsigned
 * - alpha: 16-bit unsigned fraction (0 = 0.0, 65535 = approx 1.0)
 */
module envelope_detector (
    input  wire clk,
    input  wire rst_n,
    input  wire ce,                 // New sample strobe
    input  wire signed [23:0] sample_in,
    input  wire [15:0] alpha_attack,
    input  wire [15:0] alpha_release,
    output reg [23:0] envelope_out
);

    // Absolute value of the 24-bit signed sample
    // Note: -2^23 cannot be represented as +2^23 in 24 bits, but for envelope 
    // we can use 24 bits unsigned which can hold up to 2^24-1.
    wire [23:0] abs_sample;
    assign abs_sample = sample_in[23] ? (~sample_in[23:0] + 1'b1) : sample_in[23:0];

    // Filter logic
    reg [39:0] env_acc; // 24.16 fixed point internal accumulator
    
    wire [23:0] diff;
    wire [15:0] active_alpha;
    wire [39:0] delta;
    
    // Choose between attack and release coefficients
    assign active_alpha = (abs_sample > envelope_out) ? alpha_attack : alpha_release;
    
    // delta = alpha * (abs_sample - env)
    // We treat env as 24.16 in the calculation
    // abs_sample - envelope_out is a signed 25-bit value
    wire signed [24:0] error;
    assign error = $signed({1'b0, abs_sample}) - $signed({1'b0, envelope_out});
    
    // Multiply alpha (16-bit) by error (25-bit signed)
    // Result is 41-bit signed.
    wire signed [40:0] mult_res;
    assign mult_res = $signed({1'b0, active_alpha}) * error;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            env_acc <= 40'h0;
            envelope_out <= 24'h0;
        end else if (ce) begin
            // Update accumulator: env_acc = env_acc + (alpha * error)
            // mult_res is in 16-bit fractional domain
            env_acc <= env_acc + mult_res[39:0];
            
            // Output is the integer part of the accumulator
            envelope_out <= env_acc[39:16];
        end
    end

endmodule
