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

module i2s_clock (
    input wire clk,       // 27MHz system clock
    output reg bclk,      // ~3 MHz (27 MHz / 9)
    output reg lrclk      // ~46.875 kHz (BCLK / 64)
);

    // Sub-counter for BCLK period (0 to 8 = 9 system clocks)
    reg [3:0] bclk_cnt = 0;

    // Counter for BCLK cycles within one LRCLK frame (0 to 63)
    reg [5:0] lrclk_cnt = 0;

    // Flag: a new BCLK period has just started (delayed by 1 system clock)
    reg bclk_tick = 0;

    // Single clock domain: everything driven by posedge clk
    always @(posedge clk) begin
        // BCLK generation: divide system clock by 9
        bclk_tick <= 0;
        if (bclk_cnt == 4'd8) begin
            bclk_cnt <= 0;
            bclk <= 1'b1;
            bclk_tick <= 1;    // Signal that a new BCLK period starts
        end else begin
            if (bclk_cnt == 4'd4)
                bclk <= 1'b0;
            bclk_cnt <= bclk_cnt + 1;
        end

        // LRCLK generation: advance one system clock AFTER BCLK rising edge
        // This ensures the LRCLK transition does not coincide with the same
        // BCLK edge, giving a proper 32 BCLK count between transitions.
        if (bclk_tick) begin
            if (lrclk_cnt == 6'd63) begin
                lrclk_cnt <= 0;
                lrclk <= 1'b0;       // Start Left channel (LOW)
            end else begin
                if (lrclk_cnt == 6'd31)
                    lrclk <= 1'b1;    // Switch to Right channel (HIGH)
                lrclk_cnt <= lrclk_cnt + 6'd1;
            end
        end
    end

    initial begin
        bclk = 0;
        lrclk = 0;
    end

endmodule
