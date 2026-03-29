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
 * Gain Computer for Audio Limiter
 * 
 * Takes the signal envelope and calculates the gain factor:
 * If env <= threshold, gain = 1.0 (UNITY)
 * If env >  threshold, gain = threshold / env
 * 
 * Implementation:
 * - Uses a LUT for the inverse calculation (threshold / env)
 * - Input: 24-bit envelope
 * - Table index: env[23:14] (1024 entries)
 * - Output: 25-bit gain (1.24 bit fixed-point, 1.0 = 2^24)
 */
module gain_computer (
    input  wire clk,
    input  wire [23:0] envelope_in,
    output reg [24:0] gain_out // 1 bit integer, 24 bit fraction (1.0 = 2^24)
);

    reg [24:0] gain_rom [0:1023];

    initial begin
        $readmemh("src/gain_lut.hex", gain_rom);
    end

    // The ROM lookup.
    always @(posedge clk) begin
        gain_out <= gain_rom[envelope_in[23:14]];
    end

endmodule
