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

module sine_gen (
    input wire bclk,
    input wire lrclk,
    output reg [31:0] data_out
);

    parameter PHASE_INC = 24'd178957; // 500 Hz @ 46.875 kHz

    reg [23:0] phase_acc = 0;
    reg [15:0] sine_rom [0:255];
    reg prev_lrclk = 0;

    initial begin
        $readmemh("src/sine_lut.hex", sine_rom);
    end

    always @(posedge bclk) begin
        prev_lrclk <= lrclk;
        
        // At the start of a sample (let's say negedge lrclk for the Left channel start)
        // In this implementation, I'll update at the transition.
        if (lrclk == 1'b0 && prev_lrclk == 1'b1) begin
            phase_acc <= phase_acc + PHASE_INC;
            // Map 24-bit phase to 8-bit ROM index
            data_out <= {sine_rom[phase_acc[23:16]], 16'h0000};
        end
    end

endmodule
