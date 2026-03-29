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

module i2s (
    input wire clk,          // 27MHz clock
    input wire [15:0] data_l,
    input wire [15:0] data_r,
    output reg bclk,
    output reg lrclk,
    output reg sdata,
    output wire next_sample
);

    reg [4:0] bclk_cnt = 0;
    reg [4:0] bit_cnt = 0;
    reg [31:0] shift_reg = 0;

    // BCLK generation: divide by 21 (approx)
    // 27MHz / 21 = 1.2857 MHz
    always @(posedge clk) begin
        if (bclk_cnt >= 5'd10) begin
            bclk_cnt <= 0;
            bclk <= ~bclk;
        end else begin
            bclk_cnt <= bclk_cnt + 1;
        end
    end

    // LRCLK and DATA on Falling Edge of BCLK
    always @(negedge bclk) begin
        if (bit_cnt == 5'd31) begin
            bit_cnt <= 0;
            lrclk <= ~lrclk;
            shift_reg <= {data_l, data_r};
        end else begin
            bit_cnt <= bit_cnt + 1;
            shift_reg <= {shift_reg[30:0], 1'b0};
        end
        sdata <= shift_reg[31];
    end

    assign next_sample = (bit_cnt == 5'd31) && (lrclk == 1'b1); // Pulse when LRCLK transitions

endmodule
