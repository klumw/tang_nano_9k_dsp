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

module volume_control #(
    parameter DEBOUNCE_MS = 20,
    parameter CLK_FREQ_HZ = 27_000_000
)(
    input  clk,
    input  rst_n,
    input  ready_in,     // Sample ready signal
    input  btn_vol,      // Volume button (Active Low, Pull-up)
    input  signed [23:0] audio_in,
    output signed [23:0] audio_out,
    output reg [2:0]     led_vol,   // Internal LED state (Active High mapping)
    output reg           ready_out  // Output ready signal
);

    // --- Button Debouncing and Edge Detection ---
    localparam DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    
    reg [19:0] debounce_cnt = 0;
    reg btn_r = 1'b1;        // Synchronized/Debounced button state
    reg btn_prev = 1'b1;     // Previous button state for edge detection
    
    always @(posedge clk) begin
        if (!rst_n) begin
            debounce_cnt <= 0;
            btn_r <= 1'b1;
            btn_prev <= 1'b1;
        end else begin
            // Simple debounce logic
            if (btn_vol != btn_r) begin
                if (debounce_cnt >= DEBOUNCE_CYCLES) begin
                    btn_r <= btn_vol;
                    debounce_cnt <= 0;
                end else begin
                    debounce_cnt <= debounce_cnt + 1;
                end
            end else begin
                debounce_cnt <= 0;
            end
            
            btn_prev <= btn_r;
        end
    end

    // Detect falling edge (btn pressed: 1 -> 0)
    wire btn_pressed = (btn_prev && !btn_r);

    // --- State Machine ---
    reg [1:0] state = 2'd0;  // 0: 0dB, 1: -6dB, 2: -12dB, 3: -18dB
    reg dir = 1'b0;          // 0: Decreasing (louder -> quieter), 1: Increasing (quieter -> louder)

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= 2'd0;
            dir <= 1'b0;
        end else if (btn_pressed) begin
            if (dir == 1'b0) begin
                // Counting Down (levels 0 -> 3)
                if (state == 2'd3) begin
                    state <= 2'd2;
                    dir <= 1'b1; // Turn around
                end else begin
                    state <= state + 1;
                end
            end else begin
                // Counting Up (levels 3 -> 0)
                if (state == 2'd0) begin
                    state <= 2'd1;
                    dir <= 1'b0; // Turn around
                end else begin
                    state <= state - 1;
                end
            end
        end
    end

    // --- LED Mapping (Active High Internal Representation) ---
    // Stufe 0 (0dB):   3'b111
    // Stufe 1 (-6dB):  3'b011
    // Stufe 2 (-12dB): 3'b001
    // Stufe 3 (-18dB): 3'b000
    always @(*) begin
        case (state)
            2'd0: led_vol = 3'b111;
            2'd1: led_vol = 3'b011;
            2'd2: led_vol = 3'b001;
            2'd3: led_vol = 3'b000;
            default: led_vol = 3'b000;
        endcase
    end

    // --- Gain Scaling (using Bitshifts) ---
    reg signed [23:0] audio_scaled;
    always @(*) begin
        case (state)
            2'd0: audio_scaled = audio_in;             // 0 dB: x1.0
            2'd1: audio_scaled = audio_in >>> 1;       // -6 dB: x0.5
            2'd2: audio_scaled = audio_scaled >>> 2;   // wait, no - state 2: audio_in >>> 2
            default: audio_scaled = audio_in;          // Fallback
        endcase
    end
    
    // Correction: Better to map explicitly to avoid cascading errors in always block
    reg signed [23:0] audio_out_reg;
    always @(*) begin
        case (state)
            2'd0: audio_out_reg = audio_in;
            2'd1: audio_out_reg = audio_in >>> 1;      // -6 dB
            2'd2: audio_out_reg = audio_in >>> 2;      // -12 dB
            2'd3: audio_out_reg = audio_in >>> 3;      // -18 dB
            default: audio_out_reg = audio_in;
        endcase
    end

    assign audio_out = audio_out_reg;

    // --- Control Signal Pass-through ---
    always @(posedge clk) begin
        ready_out <= ready_in;
    end

endmodule
