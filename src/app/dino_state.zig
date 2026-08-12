const std = @import("std");

/// Logical playfield matching the Agentic Dino canvas (960×340).
pub const world_w: f32 = 960;
pub const world_h: f32 = 340;

const ceiling_y: f32 = 12;
const ground_y: f32 = 318;
const gravity: f32 = 0.28;
const flap_v: f32 = -6.4;
const max_fall: f32 = 7.5;
const max_rise: f32 = -9;
const base_speed: f32 = 2.8;
const max_speed: f32 = 16;
const gap_h: f32 = 128;
const pipe_w: f32 = 52;
const flap_cooldown_s: f32 = 0.11;
const hover_y: f32 = 150;
const entry_lead_px: f32 = 240;
const entry_angle_deg: f32 = 60;
const view_curve: f32 = 2.4;
const invert_blend: f32 = 0.55;
const invert_view = true;
const auto_retry_s: f32 = 0.8;
const bird_w: f32 = 36;
const bird_h: f32 = 28;
const bird_x: f32 = 96;
const max_obstacles: usize = 12;
const frame_ref_dt: f32 = 1.0 / 60.0;

pub const Obstacle = struct {
    x: f32 = 0,
    w: f32 = pipe_w,
    gap_y: f32 = hover_y,
    gap_h: f32 = gap_h,
    cleared: bool = false,
};

pub const DinoState = struct {
    running: bool = false,
    dead: bool = false,
    autopilot: bool = true,
    score: f32 = 0,
    hi: f32 = 0,
    pipes_cleared: u32 = 0,
    speed: f32 = base_speed,
    spawn_timer: f32 = 55,
    bird_y: f32 = hover_y - bird_h / 2,
    bird_vy: f32 = 0,
    flap_cooldown: f32 = 0,
    retry_timer: f32 = 0,
    vision_target_y: f32 = hover_y,
    aim_y: ?f32 = null,
    aim_ttl: f32 = 0,
    obstacles: [max_obstacles]Obstacle = [_]Obstacle{.{}} ** max_obstacles,
    obstacle_len: usize = 0,
    rng_state: u64 = 0xc0ffee_d100,
    night: bool = false,

    pub fn init(self: *DinoState) void {
        self.* = .{};
        self.resetRun();
        self.running = false;
    }

    pub fn resetRun(self: *DinoState) void {
        self.running = true;
        self.dead = false;
        self.score = 0;
        self.pipes_cleared = 0;
        self.speed = base_speed;
        self.spawn_timer = 55;
        self.bird_y = hover_y - bird_h / 2;
        self.bird_vy = 0;
        self.flap_cooldown = 0;
        self.retry_timer = 0;
        self.aim_y = null;
        self.aim_ttl = 0;
        self.obstacle_len = 0;
        self.vision_target_y = hover_y;
        self.night = false;
    }

    pub fn flap(self: *DinoState, force: bool) void {
        if (!self.running) {
            self.resetRun();
            return;
        }
        if (self.dead) return;
        if (!force and self.flap_cooldown > 0) return;
        self.flap_cooldown = flap_cooldown_s;
        self.bird_vy = @max(max_rise, flap_v);
    }

    pub fn setAim(self: *DinoState, world_y: f32) void {
        const clamped = clampBirdY(world_y - bird_h / 2);
        self.aim_y = clamped + bird_h / 2;
        self.aim_ttl = 2.8;
    }

    pub fn tick(self: *DinoState, dt: f32) void {
        const step = if (dt <= 0) frame_ref_dt else dt;
        const frames = step / frame_ref_dt;

        if (self.dead) {
            if (self.retry_timer > 0) {
                self.retry_timer -= step;
                if (self.retry_timer <= 0) self.resetRun();
            }
            return;
        }
        if (!self.running) return;

        if (self.flap_cooldown > 0) self.flap_cooldown -= step;
        if (self.aim_ttl > 0) {
            self.aim_ttl -= step;
            if (self.aim_ttl <= 0) self.aim_y = null;
        }

        self.localFlightTick();

        self.bird_vy = @min(max_fall, self.bird_vy + gravity * frames);
        self.bird_y += self.bird_vy * frames;

        if (self.bird_y <= ceiling_y) {
            self.bird_y = ceiling_y;
            self.bird_vy = @abs(self.bird_vy) * 0.35;
        }
        if (self.bird_y + bird_h >= ground_y) {
            self.bird_y = ground_y - bird_h;
            self.kill();
            return;
        }

        self.score += self.speed * 0.12 * frames;
        self.speed = self.computeSpeed();
        self.night = self.score > 500;

        self.spawn_timer -= frames;
        if (self.spawn_timer <= 0) self.spawnObstacle();

        var i: usize = 0;
        while (i < self.obstacle_len) : (i += 1) {
            self.obstacles[i].x -= self.speed * frames;
        }
        while (self.obstacle_len > 0 and self.obstacles[0].x + self.obstacles[0].w < -40) {
            self.removeObstacle(0);
        }

        const box_x = bird_x + 6;
        const box_y = self.bird_y + 6;
        const box_w = bird_w - 12;
        const box_h = bird_h - 12;

        i = 0;
        while (i < self.obstacle_len) : (i += 1) {
            const o = self.obstacles[i];
            const top_h = o.gap_y - o.gap_h / 2;
            const bot_y = o.gap_y + o.gap_h / 2;
            if (rectsOverlap(box_x, box_y, box_w, box_h, o.x, 0, o.w, @max(0, top_h)) or
                rectsOverlap(box_x, box_y, box_w, box_h, o.x, bot_y, o.w, @max(0, ground_y - bot_y)))
            {
                self.kill();
                return;
            }
            if (!self.obstacles[i].cleared and o.x + o.w < bird_x) {
                self.obstacles[i].cleared = true;
                self.pipes_cleared += 1;
                self.score += 10;
                self.speed = self.computeSpeed();
            }
        }
    }

    fn kill(self: *DinoState) void {
        if (self.dead) return;
        self.dead = true;
        self.running = false;
        if (self.score > self.hi) self.hi = self.score;
        if (self.autopilot) self.retry_timer = auto_retry_s;
    }

    fn computeSpeed(self: *const DinoState) f32 {
        const raw = base_speed + @min(4.5, self.score / 380.0 + @as(f32, @floatFromInt(self.pipes_cleared)) * 0.15);
        return @min(max_speed, raw);
    }

    fn spawnObstacle(self: *DinoState) void {
        if (self.obstacle_len >= max_obstacles) {
            self.removeObstacle(0);
        }
        const min_gap = ceiling_y + 56 + gap_h / 2;
        const max_gap = ground_y - 48 - gap_h / 2;
        const mid = (min_gap + max_gap) / 2;
        const span = @min(90.0, max_gap - min_gap);
        const gap_y = std.math.clamp(mid + (self.nextFloat() - 0.5) * span, min_gap, max_gap);

        self.obstacles[self.obstacle_len] = .{
            .x = world_w + 24,
            .w = pipe_w,
            .gap_y = gap_y,
            .gap_h = gap_h,
            .cleared = false,
        };
        self.obstacle_len += 1;

        const shrink = @min(20.0, self.score / 120.0);
        self.spawn_timer = @max(36.0, 110.0 + self.nextFloat() * 40.0 - shrink);
    }

    fn removeObstacle(self: *DinoState, index: usize) void {
        if (index >= self.obstacle_len) return;
        var i = index;
        while (i + 1 < self.obstacle_len) : (i += 1) {
            self.obstacles[i] = self.obstacles[i + 1];
        }
        self.obstacle_len -= 1;
    }

    fn localFlightTick(self: *DinoState) void {
        if (!self.autopilot or !self.running or self.dead) return;

        const center_y = self.bird_y + bird_h / 2;
        const near_ground = self.bird_y + bird_h > ground_y - 72;
        var combo_target: f32 = hover_y;

        if (self.nearestObstacle()) |nearest| {
            if (nearest.distance < entry_lead_px + 40) {
                combo_target = visionAim(nearest.gap_y, nearest.distance, center_y);
            }
        }
        if (self.aim_y) |aim| {
            combo_target = combo_target * 0.12 + aim * 0.88;
        }
        self.vision_target_y = combo_target;

        const below_target = center_y > combo_target + 8;
        const falling_hard = self.bird_vy > 2.2;
        const too_high = center_y < combo_target - 40 and self.bird_vy < -1;
        if (too_high) return;
        if (below_target or falling_hard or near_ground) self.flap(false);
    }

    const Nearest = struct {
        distance: f32,
        gap_y: f32,
    };

    fn nearestObstacle(self: *const DinoState) ?Nearest {
        var best: ?Nearest = null;
        for (self.obstacles[0..self.obstacle_len]) |o| {
            const distance = o.x - bird_x;
            if (distance < -pipe_w) continue;
            if (best == null or distance < best.?.distance) {
                best = .{ .distance = distance, .gap_y = o.gap_y };
            }
        }
        return best;
    }

    fn nextFloat(self: *DinoState) f32 {
        self.rng_state ^= self.rng_state << 13;
        self.rng_state ^= self.rng_state >> 7;
        self.rng_state ^= self.rng_state << 17;
        return @as(f32, @floatFromInt(self.rng_state % 10_000)) / 10_000.0;
    }

    pub fn birdRect(self: *const DinoState) struct { x: f32, y: f32, w: f32, h: f32 } {
        return .{ .x = bird_x, .y = self.bird_y, .w = bird_w, .h = bird_h };
    }

    pub fn groundY(_: *const DinoState) f32 {
        return ground_y;
    }

    pub fn ceilingY(_: *const DinoState) f32 {
        return ceiling_y;
    }
};

fn clampBirdY(y: f32) f32 {
    return std.math.clamp(y, ceiling_y, ground_y - bird_h - 2);
}

fn visionAim(gap_y: f32, distance: f32, bird_center_y: f32) f32 {
    const lead = entry_lead_px;
    const u = std.math.clamp(distance / lead, 0.0, 1.0);
    const exp_w = (std.math.exp(view_curve * u) - 1) / (std.math.exp(view_curve) - 1);
    const tan_a = @tan(entry_angle_deg * std.math.pi / 180.0);
    var normal = gap_y + distance * tan_a * exp_w;
    if (bird_center_y < gap_y - 8) {
        normal = gap_y - distance * tan_a * exp_w * 0.85;
    }
    const mid = (ceiling_y + ground_y) / 2;
    const inverted = mid * 2 - normal;
    const blend: f32 = if (invert_view) invert_blend else 0;
    var target = normal * (1 - blend) + inverted * blend;
    const snap = 1 - exp_w;
    target = target * (1 - snap) + gap_y * snap;
    return std.math.clamp(target, ceiling_y + 40, ground_y - 48);
}

fn rectsOverlap(ax: f32, ay: f32, aw: f32, ah: f32, bx: f32, by: f32, bw: f32, bh: f32) bool {
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by;
}

test "dino flap lifts bird and pipe clear advances score" {
    var dino: DinoState = undefined;
    dino.init();
    dino.resetRun();
    const y0 = dino.bird_y;
    dino.flap(true);
    dino.tick(1.0 / 60.0);
    try std.testing.expect(dino.bird_y < y0);

    dino.obstacles[0] = .{
        .x = bird_x - pipe_w - 1,
        .w = pipe_w,
        .gap_y = dino.bird_y + bird_h / 2,
        .gap_h = gap_h,
        .cleared = false,
    };
    dino.obstacle_len = 1;
    const score_before = dino.score;
    dino.tick(1.0 / 60.0);
    try std.testing.expect(dino.pipes_cleared == 1);
    try std.testing.expect(dino.score > score_before);
}

test "dino dies on ground and auto-retries when autopilot" {
    var dino: DinoState = undefined;
    dino.init();
    dino.resetRun();

    // Autopilot flap logic can rescue near-ground birds; force a hard ground hit without it.
    dino.autopilot = false;
    dino.bird_y = ground_y - bird_h + 1;
    dino.bird_vy = 24;
    dino.tick(1.0 / 60.0);
    try std.testing.expect(dino.dead);

    dino.autopilot = true;
    dino.retry_timer = auto_retry_s;
    dino.tick(auto_retry_s + 0.05);
    try std.testing.expect(dino.running);
    try std.testing.expect(!dino.dead);
}
