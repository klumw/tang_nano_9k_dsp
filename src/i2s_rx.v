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

module i2s_rx (
    input wire bclk,
    input wire lrclk,
    input wire sd,
    output reg [31:0] data_l,
    output reg [31:0] data_r,
    output reg ready
);

    reg [31:0] shift_reg = 0;
    reg [5:0] bit_cnt = 0;
    reg prev_lrclk = 0;

    always @(posedge bclk) begin
        prev_lrclk <= lrclk;
        if (lrclk != prev_lrclk) begin
            // We are at the start of Pulse 1 (Delay Cycle) for the NEW channel
            // Bit 0 of the PREVIOUS channel is currently on the SD line
            bit_cnt <= 0;
            if (prev_lrclk == 1'b0) data_l <= {shift_reg[30:0], sd};
            else data_r <= {shift_reg[30:0], sd};
            ready <= 1'b1;
        end else begin
            ready <= 1'b0;
            // Pulses 2 to 32 (31 transitions total)
            if (bit_cnt < 6'd31) begin
                shift_reg <= {shift_reg[30:0], sd}; // Shift in MSB at Pulse 2, etc.
                bit_cnt <= bit_cnt + 6'd1;
            end
        end
    end

endmodule
