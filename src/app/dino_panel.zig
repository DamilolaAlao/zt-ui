const std = @import("std");
const commands = @import("../gfx/commands.zig");
const color = @import("../gfx/color.zig");
const ui_runtime = @import("../ui/ui.zig");
const dino_state = @import("dino_state.zig");

const key_space: u32 = 32;
const key_arrow_up: u32 = 38;
const key_a: u32 = 65;
const key_r: u32 = 82;

pub fn draw(ui: *ui_runtime.UI, state: *dino_state.DinoState, rect: commands.Rect) !void {
    try ui.beginPanel("Agentic Dino · zt-ui port", rect);
    const play = ui.takeRemaining().insetXY(8, 4);
    const widget_id = ui.id("dino_playfield");
    const interaction = ui.interact(widget_id, play);

    if (ui.input.keyPressed(key_space) or ui.input.keyPressed(key_arrow_up)) {
        state.flap(false);
    }
    if (ui.input.keyPressed(key_a)) {
        state.autopilot = !state.autopilot;
    }
    if (ui.input.keyPressed(key_r)) {
        state.resetRun();
    }

    if (interaction.clicked) {
        if (!state.running or state.dead) {
            state.flap(true);
        } else {
            const world = screenToWorld(play, ui.input.mousePosition());
            state.setAim(world.y);
            state.flap(false);
        }
    }

    try drawPlayfield(ui, state, play);
    ui.endPanel();
}

fn screenToWorld(play: commands.Rect, screen: commands.Vec2) commands.Vec2 {
    const sx = if (play.w > 0) (screen.x - play.x) / play.w else 0;
    const sy = if (play.h > 0) (screen.y - play.y) / play.h else 0;
    return commands.Vec2.init(sx * dino_state.world_w, sy * dino_state.world_h);
}

fn worldToScreen(play: commands.Rect, x: f32, y: f32) commands.Vec2 {
    return commands.Vec2.init(
        play.x + (x / dino_state.world_w) * play.w,
        play.y + (y / dino_state.world_h) * play.h,
    );
}

fn worldRect(play: commands.Rect, x: f32, y: f32, w: f32, h: f32) commands.Rect {
    const scale_x = play.w / dino_state.world_w;
    const scale_y = play.h / dino_state.world_h;
    return commands.Rect.init(
        play.x + x * scale_x,
        play.y + y * scale_y,
        w * scale_x,
        h * scale_y,
    );
}

fn drawPlayfield(ui: *ui_runtime.UI, state: *dino_state.DinoState, play: commands.Rect) !void {
    try ui.renderer.pushClip(play);

    const sky = if (state.night)
        color.rgba(18, 24, 48, 255)
    else
        color.rgba(126, 196, 232, 255);
    const ground_fill = if (state.night)
        color.rgba(42, 58, 40, 255)
    else
        color.rgba(92, 160, 78, 255);
    const pipe_fill = if (state.night)
        color.rgba(72, 140, 92, 255)
    else
        color.rgba(54, 168, 86, 255);
    const pipe_lip = color.rgba(255, 210, 72, 255);
    const bird_fill = color.rgba(255, 229, 102, 255);
    const bird_beak = color.rgba(240, 120, 60, 255);
    const corridor = color.rgba(255, 220, 80, 140);

    try ui.renderer.pushRect(play, sky);

    const ground_y = state.groundY();
    const ground = worldRect(play, 0, ground_y, dino_state.world_w, dino_state.world_h - ground_y);
    try ui.renderer.pushRect(ground, ground_fill);
    try ui.renderer.pushRect(
        worldRect(play, 0, ground_y - 4, dino_state.world_w, 4),
        color.rgba(60, 110, 50, 255),
    );

    // Vision corridor toward nearest gap.
    if (state.running and !state.dead) {
        var nearest_gap: ?f32 = null;
        var nearest_dist: f32 = 9999;
        const bird = state.birdRect();
        for (state.obstacles[0..state.obstacle_len]) |o| {
            const distance = o.x - bird.x;
            if (distance < -o.w) continue;
            if (distance < nearest_dist) {
                nearest_dist = distance;
                nearest_gap = o.gap_y;
            }
        }
        if (nearest_gap) |gap_y| {
            if (nearest_dist < 300) {
                var points: [2]commands.Vec2 = .{
                    worldToScreen(play, bird.x + bird.w, bird.y + bird.h / 2),
                    worldToScreen(play, bird.x + nearest_dist + 26, gap_y),
                };
                try ui.renderer.pushPolyline(points[0..], corridor, 2.0);
            }
        }
        if (state.aim_y) |aim| {
            const marker = worldRect(play, bird.x - 8, aim - 3, 48, 6);
            try ui.renderer.pushRect(marker, color.rgba(255, 120, 200, 160));
        }
    }

    for (state.obstacles[0..state.obstacle_len]) |o| {
        const top_h = o.gap_y - o.gap_h / 2;
        const bot_y = o.gap_y + o.gap_h / 2;
        if (top_h > 0) {
            try ui.renderer.pushRect(worldRect(play, o.x, 0, o.w, top_h), pipe_fill);
            try ui.renderer.pushRect(worldRect(play, o.x - 4, top_h - 14, o.w + 8, 14), pipe_lip);
        }
        const bot_h = ground_y - bot_y;
        if (bot_h > 0) {
            try ui.renderer.pushRect(worldRect(play, o.x, bot_y, o.w, bot_h), pipe_fill);
            try ui.renderer.pushRect(worldRect(play, o.x - 4, bot_y, o.w + 8, 14), pipe_lip);
        }
    }

    const bird = state.birdRect();
    const body = worldRect(play, bird.x, bird.y, bird.w, bird.h);
    try ui.renderer.pushRect(body, bird_fill);
    try ui.renderer.pushRect(
        worldRect(play, bird.x + bird.w - 8, bird.y + bird.h * 0.35, 12, 8),
        bird_beak,
    );
    try ui.renderer.pushRect(
        worldRect(play, bird.x + 10, bird.y + 8, 6, 6),
        color.rgba(30, 30, 30, 255),
    );
    // Wing
    try ui.renderer.pushRect(
        worldRect(play, bird.x + 4, bird.y + bird.h * 0.45, 14, 8),
        color.rgba(255, 200, 70, 255),
    );

    var hud_buf: [96]u8 = undefined;
    const hud = try std.fmt.bufPrint(
        &hud_buf,
        "HI {d:0>5}  {d:0>5}  ·  pipes {d}  ·  {s}",
        .{
            @as(u32, @intFromFloat(state.hi)),
            @as(u32, @intFromFloat(state.score)),
            state.pipes_cleared,
            if (state.autopilot) "AUTO" else "MANUAL",
        },
    );
    try ui.renderer.pushText(
        commands.Vec2.init(play.x + 12, play.y + 12),
        hud,
        color.rgba(20, 28, 18, 230),
        14,
    );

    if (!state.running and !state.dead) {
        try drawBanner(ui, play, "AGENTIC DINO", "Space / click to flap · A toggle autopilot");
    } else if (state.dead) {
        var over_buf: [64]u8 = undefined;
        const over = try std.fmt.bufPrint(
            &over_buf,
            "Score {d:0>5} · retry {s}",
            .{
                @as(u32, @intFromFloat(state.score)),
                if (state.autopilot) "auto" else "R / click",
            },
        );
        try drawBanner(ui, play, "RUN OVER", over);
    }

    try ui.renderer.popClip();
}

fn drawBanner(ui: *ui_runtime.UI, play: commands.Rect, title: []const u8, subtitle: []const u8) !void {
    const banner = commands.Rect.init(
        play.x + play.w * 0.18,
        play.y + play.h * 0.28,
        play.w * 0.64,
        play.h * 0.34,
    );
    try ui.renderer.pushRect(banner, color.rgba(14, 17, 12, 210));
    try ui.renderer.pushStrokeRect(banner, color.rgba(255, 229, 102, 200), 2);
    try ui.renderer.pushText(
        commands.Vec2.init(banner.x + 18, banner.y + 22),
        title,
        color.rgba(255, 229, 102, 255),
        18,
    );
    try ui.renderer.pushText(
        commands.Vec2.init(banner.x + 18, banner.y + 52),
        subtitle,
        color.rgba(242, 238, 228, 255),
        13,
    );
}
