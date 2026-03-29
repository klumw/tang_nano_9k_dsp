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

module i2s_tx (
    input wire bclk,
    input wire lrclk,
    input wire [31:0] data_l,
    input wire [31:0] data_r,
    output reg sdata
);

    reg [31:0] shift_reg = 0;
    reg [5:0] bit_cnt = 0;
    reg prev_lrclk = 0;

    always @(negedge bclk) begin
        prev_lrclk <= lrclk;

        if (lrclk != prev_lrclk) begin
            // Transition cycle (Pulse 1): DELAY
            bit_cnt <= 0;
            sdata <= 1'b0; 
            if (lrclk == 1'b0) shift_reg <= data_l;
            else shift_reg <= data_r;
        end else begin
            if (bit_cnt < 6'd32) begin
                // standard I2S: drive MSB at the cycle AFTER the WS change
                // Pulse 2: Drive Bit 31 (MSB)
                // Pulse 3..33: Drive subsequent bits
                sdata <= shift_reg[31];
                shift_reg <= {shift_reg[30:0], 1'b0};
                bit_cnt <= bit_cnt + 6'd1;
            end
        end
    end

endmodule
