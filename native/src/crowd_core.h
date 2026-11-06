// Pass 125: the crowd's hot loops in compiled code. EnemyManager.gd owns every array and every rule; this class reads and
// writes those arrays in place (bind) and does, for the creatures it can, exactly what the script's tick does, sum for sum,
// in the same order, so a run plays the same with or without it. Whatever it cannot do it hands back to the script.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

namespace godot {

struct V3 {
	float x, y, z;
};

class CrowdCore : public RefCounted {
	GDCLASS(CrowdCore, RefCounted)

protected:
	static void _bind_methods();

public:
	// What advance hands back with a creature's index (the index << 2 | this).
	enum Code {
		CODE_FULL = 0, // the script runs this creature's whole tick
		CODE_TAIL = 1, // moved; the script runs its poison, its fire, its walk's clock and its bite
		CODE_BITE = 2, // moved and walked; it bites this tick
	};
	// advance's flags: what the script holds that can change between two calls
	enum Flags {
		F_FREEZE = 1, // the arena's freeze, or a decoy out: every standing creature goes to the script
		F_WATCH = 2, // a boss barrier has onlookers (onlook)
		F_FLEE = 4, // someone flees on a hit (_flee)
		F_CORPSE_AIR = 8, // a body is in the air (_corpse_air)
		F_BURST = 16, // a body waits for its blast (_burst_bodies)
	};

	int version() const;
	bool bind(const Array &p_arrays);
	void set_scalars(const PackedFloat64Array &p_s);
	int64_t rebuild_grid(int p_gw, double p_g_half, int p_sw, double p_s_half, double p_sep_cell, double p_big_r);
	double grid_max_r() const;
	PackedInt32Array big_list() const;
	void set_obstacles(const Array &p_obstacles, double p_cell, double p_margin);
	void refresh_drawn(const PackedFloat32Array &p_planes, const Vector3 &p_cam_up, const Vector3 &p_cpos, const Vector3 &p_scf, double p_look_s, double p_cam_b, double p_cam_t, double p_badge, int p_parity);
	int64_t advance(int p_start, int p_boss, int p_flags);
	PackedFloat64Array tick_stats() const;
	Vector3 last_v() const;
	PackedInt64Array pass_counts() const;
	PackedInt32Array alive_of_flag(const PackedByteArray &p_flags) const;
	Vector3 sep_push(int p_i, double p_steer_k_unused);

	// the draw (crowd_render.cpp)
	void set_type_mm(int p_t, const RID &p_mm);
	int64_t render(const Array &p_render, const PackedFloat64Array &p_s);
	void put_instance(int p_t, int p_k, const PackedFloat32Array &p_row);
	void render_finish(const RID &p_shadow_mm, int p_shadow_n, int p_warm);
	PackedInt32Array render_counts() const;
	PackedInt32Array render_escapes() const;
	void put_shadow(int p_k, const PackedFloat32Array &p_row);
	int render_shadow_n() const;
	int render_reserve_shadow();
	void shadow_cache_clear();

private:
	// ---- the creatures' arrays, bound for a tick (never kept across a resize: bind runs before each use)
	V3 *pos = nullptr, *vel = nullptr, *kb = nullptr, *intent = nullptr;
	uint8_t *alive = nullptr, *hidden = nullptr, *held = nullptr, *flip = nullptr, *away = nullptr, *view = nullptr, *drawn_vis = nullptr, *vspecial = nullptr, *flash_hot = nullptr, *onlook = nullptr, *vis_hold = nullptr;
	int32_t *type_idx = nullptr, *elite_idx = nullptr, *state = nullptr, *st_last = nullptr;
	float *timer = nullptr, *anim_t = nullptr, *flash = nullptr, *squash = nullptr, *max_hp = nullptr, *speed = nullptr, *radius = nullptr, *size = nullptr, *contact_cd = nullptr, *cooldown = nullptr, *hamper_t = nullptr, *hamper_f = nullptr, *status_t = nullptr, *shove_t = nullptr, *ign_t = nullptr, *rise_t = nullptr, *rise_v = nullptr, *view_t = nullptr, *frenzy_t = nullptr, *freeze_t = nullptr, *stun_t = nullptr, *slow_t = nullptr, *mark_t = nullptr, *spin_t = nullptr, *lift_t = nullptr, *lift_cd = nullptr, *lift_h = nullptr, *wade_k = nullptr, *heights = nullptr;
	int32_t *g_head = nullptr, *g_next = nullptr, *s_head = nullptr, *s_next = nullptr, *bg_head = nullptr, *bg_j = nullptr, *bg_next = nullptr;
	int64_t g_head_n = 0, s_head_n = 0, bg_head_n = 0, bg_cap = 0;
	// per type
	uint8_t *t_faces = nullptr, *t_eight = nullptr, *t_big = nullptr, *t_plain = nullptr, *t_gear = nullptr, *t_far = nullptr, *t_badge = nullptr;
	float *t_run_fps = nullptr, *t_die_fps = nullptr, *t_cv = nullptr, *t_sh = nullptr, *t_ddrop = nullptr, *t_dslide = nullptr;
	double *t_head = nullptr;
	Array poison_src, fire_src;
	Dictionary flee, corpse_air, burst_bodies;
	int pool_max = 0;

	// ---- this tick's numbers (set_scalars)
	double delta = 0.0, sdt = 0.0, sdt_base = 0.0, poison_slow = 0.0, pace = 1.0, arena = 66.0;
	int tick = 0, phase = 0, every = 2, far_every = 4;
	bool far_push = true, far_on = false, far_bosses = true;
	double far_d = 12.0, far_ramp = 24.0, far_max = 3.0, far_cap = 6.0;
	int far_curve = 2;
	V3 ppos{ 0, 0, 0 }, cf{ 0, 0, -1 };
	int hmode = 0, grid_n = 0;
	double size_m = 0.0, resolution = 1.0;

	// ---- the separation grid's shape and the wide bodies (rebuild_grid)
	int sw = 0;
	double s_half = 0.0, sep_cell = 1.25, big_r = 0.625, grid_max = 0.0;
	int bg_n = 0;
	std::vector<int32_t> big;

	// ---- the map's obstacles by cell (the script's _obst_cells, as a dense table)
	struct Obst {
		float x, y, z;
	};
	std::vector<Obst> obst;
	int ob_x0 = 0, ob_z0 = 0, ob_w = 0, ob_h = 0;
	double ob_cell = 4.0;
	std::vector<int32_t> ob_start, ob_list;

	// ---- what the pass kept
	double crowd_hp = 0.0;
	int crowd_n = 0, poisoned = 0;
	// creatures the pass ran whole, dying bodies it ran, and those it handed back (whole, tail, bite), since the library was made
	int64_t n_plain = 0, n_dying = 0, n_full = 0, n_tail = 0, n_bite = 0, n_dying_full = 0;
	V3 v_last{ 0, 0, 0 };

	// ---- the sim's own steps
	double height_at(double x, double z) const;
	V3 clamp_arena(V3 p) const;
	bool steer_due(int i, int ti, int boss) const;
	double steer_dt(int i);
	double far_k(int i, int ti, double dist, double spd) const;
	bool obst_near(double x, double z) const;
	V3 obst_push(V3 pi, double my_r) const;
	V3 sep_sum(int i, double my_r);
	void steer_plain(int i, int ti, double dt, double steer_k, bool poison_on);
	void face_and_view(int i, int ti, V3 v);

	// ---- the draw (crowd_render.cpp)
	struct TypeDraw {
		RID mm;
		std::vector<float> dummy;
		PackedFloat32Array buf;
		int count = 0, last = 0;
	};
	std::vector<TypeDraw> tdraw;
	PackedFloat32Array shadow_buf;
	// the shadows' draped transforms, kept while a creature stands within SHADOW_CACHE_MOVE of where it was draped
	struct ShadowCache {
		std::vector<V3> at;
		std::vector<float> type, shs;
		std::vector<float> row;
		V3 cf{ 0, 0, 0 };
	};
	ShadowCache g_shc;
	int shadow_n = 0, last_shadow = 0;
	std::vector<int32_t> escapes;
	PackedInt32Array counts_out;
};

} // namespace godot

VARIANT_ENUM_CAST(godot::CrowdCore::Code);
VARIANT_ENUM_CAST(godot::CrowdCore::Flags);
