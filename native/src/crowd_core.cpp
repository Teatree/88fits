// Pass 125: the crowd's tick. Every sum below follows core/systems/EnemyManager.gd line for line, with the script's number
// types kept: a GDScript float is a double, a Vector3 component and a PackedFloat32Array element a float, so
//   var d := pos[i] - pos[j]        is float arithmetic (V3),
//   var l := sqrt(l2)               is double arithmetic on a float's value,
//   sep += d / l * (min_d - l)      divides and multiplies a V3 by doubles cast to float (Vector3's operators take real_t),
// and a value stored in a float array is cast at the store. game/tools/_p125_NATIVE_proof.gd proves a whole run the same.
#include "crowd_core.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>

using namespace godot;

namespace {

const int STATE_MOVE = 0;
const int STATE_DYING = 3;
const int STATE_WINDUP = 1;
const int STATE_CHARGE = 2;
const double CELL = 2.5;
const double DIE_SINK = 0.3;
const double CORPSE_STOP = 0.05;
const double CORPSE_GROUND_DECAY = 6.0;
const double ATTACK_FPS = 3.0;
const double FLIP_BAND = 0.2;
const double PI_D = 3.14159265358979323846;
const double VIEW_HYST = PI_D * 0.07;
const double VIEW_MIN = 0.25;
const double VIEW_LO[5] = { PI_D * 0.875, 0.0, PI_D * 0.375, PI_D * 0.125, PI_D * 0.625 };
const double VIEW_HI[5] = { PI_D, PI_D * 0.125, PI_D * 0.625, PI_D * 0.375, PI_D * 0.875 };
const int CV_N = 8;
const int FAR_NEVER = 0;
const int FAR_BOSS = 2;
const double VIS_BORDER_M = 1.0;
const double VIS_STRETCH = 1.3;
const double ROCK = 0.05;
const double BOUNCE = 0.035;
const int VIS_HOLD = 6;

inline V3 add(V3 a, V3 b) { return V3{ a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V3 sub(V3 a, V3 b) { return V3{ a.x - b.x, a.y - b.y, a.z - b.z }; }
inline V3 mul(V3 a, float s) { return V3{ a.x * s, a.y * s, a.z * s }; }
inline V3 divf(V3 a, float s) { return V3{ a.x / s, a.y / s, a.z / s }; }
inline float len2(V3 a) {
	const float x2 = a.x * a.x;
	const float y2 = a.y * a.y;
	const float z2 = a.z * a.z;
	return x2 + y2 + z2;
}
inline float len(V3 a) { return std::sqrt(len2(a)); }
inline float dot(V3 a, V3 b) {
	const float xx = a.x * b.x;
	const float yy = a.y * b.y;
	const float zz = a.z * b.z;
	return xx + yy + zz;
}
inline V3 norm(V3 a) {
	const float l2 = len2(a);
	if (l2 == 0.0f) {
		return V3{ 0.0f, 0.0f, 0.0f };
	}
	const float l = std::sqrt(l2);
	return V3{ a.x / l, a.y / l, a.z / l };
}
inline double dmax(double a, double b) { return a < b ? b : a; }
inline double dmin(double a, double b) { return b < a ? b : a; }
inline double dclamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline int iclamp(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline int ifloor(double v) { return (int)std::floor(v); }

template <typename T>
inline T *wptr(const T *p) { return const_cast<T *>(p); }

} // namespace

void CrowdCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("version"), &CrowdCore::version);
	ClassDB::bind_method(D_METHOD("bind", "arrays"), &CrowdCore::bind);
	ClassDB::bind_method(D_METHOD("set_scalars", "s"), &CrowdCore::set_scalars);
	ClassDB::bind_method(D_METHOD("rebuild_grid", "gw", "g_half", "sw", "s_half", "sep_cell", "big_r"), &CrowdCore::rebuild_grid);
	ClassDB::bind_method(D_METHOD("grid_max_r"), &CrowdCore::grid_max_r);
	ClassDB::bind_method(D_METHOD("big_list"), &CrowdCore::big_list);
	ClassDB::bind_method(D_METHOD("set_obstacles", "obstacles", "cell", "margin"), &CrowdCore::set_obstacles);
	ClassDB::bind_method(D_METHOD("refresh_drawn", "planes", "cam_up", "cpos", "scf", "look_s", "cam_b", "cam_t", "badge", "parity"), &CrowdCore::refresh_drawn);
	ClassDB::bind_method(D_METHOD("advance", "start", "boss", "flags"), &CrowdCore::advance);
	ClassDB::bind_method(D_METHOD("tick_stats"), &CrowdCore::tick_stats);
	ClassDB::bind_method(D_METHOD("last_v"), &CrowdCore::last_v);
	ClassDB::bind_method(D_METHOD("pass_counts"), &CrowdCore::pass_counts);
	ClassDB::bind_method(D_METHOD("alive_of_flag", "flags"), &CrowdCore::alive_of_flag);
	ClassDB::bind_method(D_METHOD("sep_push", "i", "unused"), &CrowdCore::sep_push);
	ClassDB::bind_method(D_METHOD("set_type_mm", "t", "mm"), &CrowdCore::set_type_mm);
	ClassDB::bind_method(D_METHOD("render", "arrays", "s"), &CrowdCore::render);
	ClassDB::bind_method(D_METHOD("put_instance", "t", "k", "row"), &CrowdCore::put_instance);
	ClassDB::bind_method(D_METHOD("put_shadow", "k", "row"), &CrowdCore::put_shadow);
	ClassDB::bind_method(D_METHOD("render_finish", "shadow_mm", "shadow_n", "warm"), &CrowdCore::render_finish);
	ClassDB::bind_method(D_METHOD("render_counts"), &CrowdCore::render_counts);
	ClassDB::bind_method(D_METHOD("render_escapes"), &CrowdCore::render_escapes);
	ClassDB::bind_method(D_METHOD("render_shadow_n"), &CrowdCore::render_shadow_n);
	ClassDB::bind_method(D_METHOD("render_reserve_shadow"), &CrowdCore::render_reserve_shadow);
	ClassDB::bind_method(D_METHOD("shadow_cache_clear"), &CrowdCore::shadow_cache_clear);
	BIND_ENUM_CONSTANT(CODE_FULL);
	BIND_ENUM_CONSTANT(CODE_TAIL);
	BIND_ENUM_CONSTANT(CODE_BITE);
	BIND_ENUM_CONSTANT(F_FREEZE);
	BIND_ENUM_CONSTANT(F_WATCH);
	BIND_ENUM_CONSTANT(F_FLEE);
	BIND_ENUM_CONSTANT(F_CORPSE_AIR);
	BIND_ENUM_CONSTANT(F_BURST);
}

int CrowdCore::version() const {
	return 1;
}

// The arrays in EnemyManager._nat_arrays' order. True when every per-creature array is pool_max long; the script's own tick
// runs otherwise. A packed array in a Variant is shared by reference and holds one buffer, so the pointers taken here are
// the script's own storage; the temporaries below only hold it for the length of this call.
bool CrowdCore::bind(const Array &a) {
	int k = 0;
	pool_max = int(a[k++]);
	bool ok = true;
#define BIND_V3(name)                                 \
	{                                                 \
		PackedVector3Array p = a[k++];                \
		ok = ok && p.size() >= pool_max;              \
		name = reinterpret_cast<V3 *>(wptr(p.ptr())); \
	}
#define BIND_U8(name)                    \
	{                                    \
		PackedByteArray p = a[k++];      \
		ok = ok && p.size() >= pool_max; \
		name = wptr(p.ptr());            \
	}
#define BIND_I32(name)                   \
	{                                    \
		PackedInt32Array p = a[k++];     \
		ok = ok && p.size() >= pool_max; \
		name = wptr(p.ptr());            \
	}
#define BIND_F32(name)                   \
	{                                    \
		PackedFloat32Array p = a[k++];   \
		ok = ok && p.size() >= pool_max; \
		name = wptr(p.ptr());            \
	}
#define BIND_T_U8(name)             \
	{                               \
		PackedByteArray p = a[k++]; \
		name = wptr(p.ptr());       \
	}
#define BIND_T_F32(name)               \
	{                                  \
		PackedFloat32Array p = a[k++]; \
		name = wptr(p.ptr());          \
	}
	BIND_V3(pos)
	BIND_V3(vel)
	BIND_V3(kb)
	BIND_V3(intent)
	BIND_U8(alive)
	BIND_U8(hidden)
	BIND_U8(held)
	BIND_U8(flip)
	BIND_U8(away)
	BIND_U8(view)
	BIND_U8(drawn_vis)
	BIND_U8(vspecial)
	BIND_U8(flash_hot)
	BIND_U8(onlook)
	BIND_U8(vis_hold)
	BIND_I32(type_idx)
	BIND_I32(elite_idx)
	BIND_I32(state)
	BIND_I32(st_last)
	BIND_F32(timer)
	BIND_F32(anim_t)
	BIND_F32(flash)
	BIND_F32(squash)
	BIND_F32(max_hp)
	BIND_F32(speed)
	BIND_F32(radius)
	BIND_F32(size)
	BIND_F32(contact_cd)
	BIND_F32(cooldown)
	BIND_F32(hamper_t)
	BIND_F32(hamper_f)
	BIND_F32(status_t)
	BIND_F32(shove_t)
	BIND_F32(ign_t)
	BIND_F32(rise_t)
	BIND_F32(rise_v)
	BIND_F32(view_t)
	BIND_F32(frenzy_t)
	BIND_F32(freeze_t)
	BIND_F32(stun_t)
	BIND_F32(slow_t)
	BIND_F32(mark_t)
	BIND_F32(spin_t)
	BIND_F32(lift_t)
	BIND_F32(lift_cd)
	BIND_F32(lift_h)
	BIND_F32(wade_k)
	{
		PackedFloat32Array p = a[k++];
		heights = wptr(p.ptr());
	}
	{
		PackedInt32Array p = a[k++];
		g_head = wptr(p.ptr());
		g_head_n = p.size();
	}
	{
		PackedInt32Array p = a[k++];
		g_next = wptr(p.ptr());
		ok = ok && p.size() >= pool_max;
	}
	{
		PackedInt32Array p = a[k++];
		s_head = wptr(p.ptr());
		s_head_n = p.size();
	}
	{
		PackedInt32Array p = a[k++];
		s_next = wptr(p.ptr());
		ok = ok && p.size() >= pool_max;
	}
	{
		PackedInt32Array p = a[k++];
		bg_head = wptr(p.ptr());
		bg_head_n = p.size();
	}
	{
		PackedInt32Array p = a[k++];
		bg_j = wptr(p.ptr());
		bg_cap = p.size();
	}
	{
		PackedInt32Array p = a[k++];
		bg_next = wptr(p.ptr());
		bg_cap = std::min<int64_t>(bg_cap, p.size());
	}
	BIND_T_U8(t_faces)
	BIND_T_U8(t_eight)
	BIND_T_U8(t_big)
	BIND_T_U8(t_plain)
	BIND_T_U8(t_gear)
	BIND_T_U8(t_far)
	BIND_T_U8(t_badge)
	BIND_T_F32(t_run_fps)
	BIND_T_F32(t_die_fps)
	BIND_T_F32(t_cv)
	BIND_T_F32(t_sh)
	BIND_T_F32(t_ddrop)
	{
		PackedFloat64Array p = a[k++];
		t_head = wptr(p.ptr());
	}
	poison_src = a[k++];
	fire_src = a[k++];
	flee = a[k++];
	corpse_air = a[k++];
	burst_bodies = a[k++];
	ok = ok && poison_src.size() >= pool_max && fire_src.size() >= pool_max;
	return ok;
}

void CrowdCore::set_scalars(const PackedFloat64Array &p_s) {
	const double *s = p_s.ptr();
	int k = 0;
	delta = s[k++];
	sdt = s[k++];
	sdt_base = s[k++];
	tick = (int)s[k++];
	phase = (int)s[k++];
	every = (int)s[k++];
	far_every = (int)s[k++];
	far_push = s[k++] != 0.0;
	ppos.x = (float)s[k++];
	ppos.y = (float)s[k++];
	ppos.z = (float)s[k++];
	pace = s[k++];
	poison_slow = s[k++];
	far_on = s[k++] != 0.0;
	far_d = s[k++];
	far_ramp = s[k++];
	far_max = s[k++];
	far_curve = (int)s[k++];
	far_cap = s[k++];
	far_bosses = s[k++] != 0.0;
	arena = s[k++];
	cf.x = (float)s[k++];
	cf.y = (float)s[k++];
	cf.z = (float)s[k++];
	hmode = (int)s[k++];
	size_m = s[k++];
	resolution = s[k++];
	grid_n = (int)s[k++];
	crowd_hp = 0.0;
	crowd_n = 0;
	poisoned = 0;
}

// _rebuild_grid's loop and _sep_bigs. bg_n, or minus the entries the wide bodies' lists need when they outgrow the arrays
// (the script makes them longer and asks again).
int64_t CrowdCore::rebuild_grid(int p_gw, double p_g_half, int p_sw, double p_s_half, double p_sep_cell, double p_big_r) {
	sw = p_sw;
	s_half = p_s_half;
	sep_cell = p_sep_cell;
	big_r = p_big_r;
	const int gw = p_gw;
	std::fill(g_head, g_head + g_head_n, -1);
	std::fill(s_head, s_head + s_head_n, -1);
	big.clear();
	grid_max = 0.0;
	const double g_half = p_g_half;
	for (int i = pool_max - 1; i >= 0; i--) {
		if (alive[i] == 0 || state[i] == STATE_DYING || hidden[i] == 1 || held[i] == 1) {
			continue;
		}
		const double px = pos[i].x;
		const double pz = pos[i].z;
		const int c = iclamp((int)((pz + g_half) / CELL), 0, gw - 1) * gw + iclamp((int)((px + g_half) / CELL), 0, gw - 1);
		g_next[i] = g_head[c];
		g_head[c] = i;
		const int sc = iclamp((int)((pz + s_half) / sep_cell), 0, sw - 1) * sw + iclamp((int)((px + s_half) / sep_cell), 0, sw - 1);
		s_next[i] = s_head[sc];
		s_head[sc] = i;
		const double r = radius[i];
		if (r > grid_max) {
			grid_max = r;
		}
		if (r > big_r) {
			big.push_back(i);
		}
	}
	std::fill(bg_head, bg_head + bg_head_n, -1);
	int64_t n = 0;
	for (const int32_t j : big) {
		const double reach = big_r + (double)radius[j];
		const int x0 = iclamp(ifloor(((double)pos[j].x - reach + s_half) / sep_cell), 0, sw - 1);
		const int x1 = iclamp(ifloor(((double)pos[j].x + reach + s_half) / sep_cell), 0, sw - 1);
		const int z0 = iclamp(ifloor(((double)pos[j].z - reach + s_half) / sep_cell), 0, sw - 1);
		const int z1 = iclamp(ifloor(((double)pos[j].z + reach + s_half) / sep_cell), 0, sw - 1);
		for (int cz = z0; cz <= z1; cz++) {
			for (int cx = x0; cx <= x1; cx++) {
				if (n < bg_cap) {
					const int c = cz * sw + cx;
					bg_j[n] = j;
					bg_next[n] = bg_head[c];
					bg_head[c] = (int32_t)n;
				}
				n++;
			}
		}
	}
	if (n > bg_cap) {
		return -n;
	}
	bg_n = (int)n;
	return n;
}

double CrowdCore::grid_max_r() const {
	return grid_max;
}

// The wide bodies the last grid found, in its order (the script's _big).
PackedInt32Array CrowdCore::big_list() const {
	PackedInt32Array out;
	if (!big.empty()) {
		out.resize((int64_t)big.size());
		std::memcpy(out.ptrw(), big.data(), big.size() * sizeof(int32_t));
	}
	return out;
}

// _obstacle_cells: each obstacle listed, in the map's order, in every cell its circle widened by `margin` reaches.
void CrowdCore::set_obstacles(const Array &p_obstacles, double p_cell, double p_margin) {
	ob_cell = p_cell;
	const int n = p_obstacles.size();
	obst.resize(n);
	int x0 = 0, x1 = -1, z0 = 0, z1 = -1;
	std::vector<int> cells;
	for (int k = 0; k < n; k++) {
		const Vector3 o = p_obstacles[k];
		obst[k] = Obst{ o.x, o.y, o.z };
		const double reach = (double)o.z + p_margin;
		const int a0 = ifloor(((double)o.x - reach) / ob_cell), a1 = ifloor(((double)o.x + reach) / ob_cell);
		const int b0 = ifloor(((double)o.y - reach) / ob_cell), b1 = ifloor(((double)o.y + reach) / ob_cell);
		if (x1 < x0) {
			x0 = a0;
			x1 = a1;
			z0 = b0;
			z1 = b1;
		} else {
			x0 = std::min(x0, a0);
			x1 = std::max(x1, a1);
			z0 = std::min(z0, b0);
			z1 = std::max(z1, b1);
		}
	}
	ob_x0 = x0;
	ob_z0 = z0;
	ob_w = x1 >= x0 ? x1 - x0 + 1 : 0;
	ob_h = z1 >= z0 ? z1 - z0 + 1 : 0;
	std::vector<std::vector<int32_t>> lists((size_t)ob_w * ob_h);
	for (int k = 0; k < n; k++) {
		const Obst &o = obst[k];
		const double reach = (double)o.z + p_margin;
		for (int cx = ifloor(((double)o.x - reach) / ob_cell); cx <= ifloor(((double)o.x + reach) / ob_cell); cx++) {
			for (int cz = ifloor(((double)o.y - reach) / ob_cell); cz <= ifloor(((double)o.y + reach) / ob_cell); cz++) {
				lists[(size_t)(cz - ob_z0) * ob_w + (cx - ob_x0)].push_back(k);
			}
		}
	}
	ob_start.assign(lists.size() + 1, 0);
	ob_list.clear();
	for (size_t c = 0; c < lists.size(); c++) {
		ob_start[c] = (int32_t)ob_list.size();
		ob_list.insert(ob_list.end(), lists[c].begin(), lists[c].end());
	}
	ob_start[lists.size()] = (int32_t)ob_list.size();
}

bool CrowdCore::obst_near(double x, double z) const {
	const int cx = ifloor(x / ob_cell) - ob_x0;
	const int cz = ifloor(z / ob_cell) - ob_z0;
	if (cx < 0 || cz < 0 || cx >= ob_w || cz >= ob_h) {
		return false;
	}
	const size_t c = (size_t)cz * ob_w + cx;
	return ob_start[c + 1] > ob_start[c];
}

// MapBase.height_at (hmode 1), or the flat ground of a manager with no height function (hmode 0).
double CrowdCore::height_at(double x, double z) const {
	if (hmode == 0 || grid_n == 0) {
		return 0.0;
	}
	const double half = size_m * 0.5;
	const double top = (double)(grid_n - 1) - 0.001;
	const double fx = dclamp((x + half) * resolution, 0.0, top);
	const double fz = dclamp((z + half) * resolution, 0.0, top);
	const int ix = (int)fx;
	const int iz = (int)fz;
	const double tx = fx - (double)ix;
	const double tz = fz - (double)iz;
	const double h00 = heights[iz * grid_n + ix];
	const double h10 = heights[iz * grid_n + ix + 1];
	const double h01 = heights[(iz + 1) * grid_n + ix];
	const double h11 = heights[(iz + 1) * grid_n + ix + 1];
	const double a = h00 + (h10 - h00) * tx;
	const double b = h01 + (h11 - h01) * tx;
	return a + (b - a) * tz;
}

// _clamp_arena: Vector2's length and normalized, in floats.
V3 CrowdCore::clamp_arena(V3 p) const {
	float fx = p.x, fz = p.z;
	const float x2 = fx * fx;
	const float z2 = fz * fz;
	const float l2 = x2 + z2;
	const float l = std::sqrt(l2);
	const double lim = arena - 2.0;
	if ((double)l > lim) {
		if (l2 != 0.0f) {
			fx /= l;
			fz /= l;
		}
		const float s = (float)lim;
		fx *= s;
		fz *= s;
	}
	return V3{ fx, p.y, fz };
}

// _steer_due, for a creature in the plain walk (never winding up or charging).
bool CrowdCore::steer_due(int i, int ti, int boss) const {
	if ((i % every) != phase) {
		return false;
	}
	if (far_every <= every || drawn_vis[i] == 1 || i == boss || elite_idx[i] >= 0 || t_big[ti] == 1) {
		return true;
	}
	if (vspecial[i] == 1 || t_gear[ti] == 1) {
		return true;
	}
	int m = (tick - i) % far_every;
	if (m < 0) {
		m += far_every;
	}
	if (m == 0) {
		return true;
	}
	return obst_near(pos[i].x, pos[i].z);
}

// _steer_dt
double CrowdCore::steer_dt(int i) {
	const int last = st_last[i];
	st_last[i] = tick;
	const int n = tick - last;
	if (last < 0 || n == every || n > std::max(far_every, every)) {
		return sdt;
	}
	return delta * (double)n;
}

// far_speed_k with far_speed_mult
double CrowdCore::far_k(int i, int ti, double dist, double spd) const {
	const int kind = t_far[ti];
	if (kind == FAR_NEVER || (kind == FAR_BOSS && !far_bosses) || elite_idx[i] >= 0 || vspecial[i] == 1) {
		return 1.0;
	}
	double m = 1.0;
	if (!(dist <= far_d)) {
		const double f = far_ramp <= 0.0 ? 1.0 : dclamp((dist - far_d) / far_ramp, 0.0, 1.0);
		double s = f * f * (3.0 - 2.0 * f);
		if (far_curve == 1) {
			s = f;
		} else if (far_curve == 2) {
			s = 1.0 - (1.0 - f) * (1.0 - f);
		} else if (far_curve == 3) {
			s = f * f;
		}
		m = 1.0 + (far_max - 1.0) * s;
	}
	if (far_cap > 0.0 && spd > 0.0 && spd * m > far_cap) {
		m = dmax(1.0, far_cap / spd);
	}
	return m;
}

// _steer's separation, the wide bodies past its cells, and _obstacle_push, summed in the script's order.
V3 CrowdCore::sep_sum(int i, double my_r) {
	V3 sep{ 0.0f, 0.0f, 0.0f };
	const V3 pi = pos[i];
	const int gx = iclamp((int)(((double)pi.x + s_half) / sep_cell), 0, sw - 1);
	const int gz = iclamp((int)(((double)pi.z + s_half) / sep_cell), 0, sw - 1);
	int reach = 1;
	if (my_r > big_r) {
		reach = std::max((int)std::ceil((my_r + grid_max) / sep_cell), 1);
	}
	const int cx1 = std::min(gx + reach + 1, sw);
	const int cz0 = std::max(gz - reach, 0);
	const int cz1 = std::min(gz + reach + 1, sw);
	for (int cx = std::max(gx - reach, 0); cx < cx1; cx++) {
		for (int cz = cz0; cz < cz1; cz++) {
			int j = s_head[cz * sw + cx];
			while (j >= 0) {
				if (j != i) {
					V3 d = sub(pi, pos[j]);
					d.y = 0.0f;
					const double min_d = my_r + (double)radius[j];
					const double l2 = len2(d);
					if (l2 < min_d * min_d && l2 > 0.0001) {
						const double l = std::sqrt(l2);
						const V3 a = mul(divf(d, (float)l), (float)(min_d - l));
						sep = add(sep, divf(a, (float)min_d));
					}
				}
				j = s_next[j];
			}
		}
	}
	if (my_r <= big_r && bg_n > 0) {
		int e = bg_head[gz * sw + gx];
		while (e >= 0) {
			const int j = bg_j[e];
			e = bg_next[e];
			if (j == i) {
				continue;
			}
			const int jx = iclamp((int)(((double)pos[j].x + s_half) / sep_cell), 0, sw - 1);
			const int jz = iclamp((int)(((double)pos[j].z + s_half) / sep_cell), 0, sw - 1);
			if (std::abs(jx - gx) <= 1 && std::abs(jz - gz) <= 1) {
				continue;
			}
			V3 d = sub(pi, pos[j]);
			d.y = 0.0f;
			const double min_d = my_r + (double)radius[j];
			const double l2 = len2(d);
			if (l2 < min_d * min_d && l2 > 0.0001) {
				const double l = std::sqrt(l2);
				const V3 a = mul(divf(d, (float)l), (float)(min_d - l));
				sep = add(sep, divf(a, (float)min_d));
			}
		}
	}
	return add(sep, obst_push(pi, my_r));
}

// _obstacle_push: only the obstacles whose cell list reaches its cell, summed in the map's order.
V3 CrowdCore::obst_push(V3 pi, double my_r) const {
	V3 push{ 0.0f, 0.0f, 0.0f };
	const int ocx = ifloor((double)pi.x / ob_cell) - ob_x0;
	const int ocz = ifloor((double)pi.z / ob_cell) - ob_z0;
	if (ocx >= 0 && ocz >= 0 && ocx < ob_w && ocz < ob_h) {
		const size_t c = (size_t)ocz * ob_w + ocx;
		for (int32_t q = ob_start[c]; q < ob_start[c + 1]; q++) {
			const Obst &o = obst[ob_list[q]];
			const V3 d{ (float)((double)pi.x - (double)o.x), 0.0f, (float)((double)pi.z - (double)o.y) };
			const double l2 = len2(d);
			const double min_d = (double)o.z + my_r;
			if (l2 < min_d * min_d && l2 > 0.0001) {
				const double l = std::sqrt(l2);
				const V3 a = mul(divf(d, (float)l), (float)(min_d - l));
				push = add(push, mul(a, 3.0f));
			}
		}
	}
	return push;
}

// The push the script's _steer asks for a creature of any brain (no ghost, no shove).
Vector3 CrowdCore::sep_push(int p_i, double) {
	const V3 s = sep_sum(p_i, (double)radius[p_i]);
	return Vector3(s.x, s.y, s.z);
}

// _steer for a creature walking at the hero (chase, flock) in the plain state.
void CrowdCore::steer_plain(int i, int ti, double dt, double steer_k, bool poison_on) {
	V3 to = sub(ppos, pos[i]);
	to.y = 0.0f;
	const double dist = len(to);
	const V3 dir = dist > 0.001 ? divf(to, (float)dist) : V3{ 0.0f, 0.0f, 0.0f };
	double spd = speed[i];
	if (frenzy_t[i] > 0.0f) {
		frenzy_t[i] = (float)((double)frenzy_t[i] - dt);
		spd *= 1.3;
	}
	if (freeze_t[i] > 0.0f) {
		freeze_t[i] = (float)((double)freeze_t[i] - dt);
	}
	if (stun_t[i] > 0.0f) {
		stun_t[i] = (float)((double)stun_t[i] - dt);
		vel[i] = V3{ 0.0f, 0.0f, 0.0f };
		intent[i] = V3{ 0.0f, 0.0f, 0.0f };
		return;
	}
	if (mark_t[i] > 0.0f) {
		mark_t[i] = (float)((double)mark_t[i] - dt);
		flash[i] = (float)dmax((double)flash[i], 0.35);
		flash_hot[i] = 1;
	}
	if (poison_slow > 0.0 && poison_on) {
		spd *= 1.0 - dclamp(poison_slow, 0.0, 0.9);
	}
	if (far_on && dist > far_d) {
		spd *= far_k(i, ti, dist, spd);
	}
	V3 desired;
	if (t_plain[ti] == 2) {
		// flock: its wobble fans a pack out
		const double a1 = (double)anim_t[i] * 1.7 + (double)i;
		const double a2 = (double)anim_t[i] * 1.3 + (double)i * 0.7;
		const V3 wob = mul(V3{ (float)std::sin(a1), 0.0f, (float)std::cos(a2) }, 0.6f);
		desired = mul(norm(add(dir, mul(wob, 0.5f))), (float)spd);
	} else {
		desired = mul(dir, (float)spd);
	}
	const V3 sep = sep_sum(i, (double)radius[i]);
	vel[i] = add(desired, mul(sep, (float)(4.0 * steer_k)));
	intent[i] = desired;
}

// The tick's facing, for one moving by `v` (a plain walker: no brain of its own to face by).
void CrowdCore::face_and_view(int i, int ti, V3 v) {
	const V3 face = v;
	if (t_eight[ti] == 1) {
		if ((double)len2(face) > 0.04) {
			const V3 cr{ -cf.z, 0.0f, cf.x };
			const double fwd = dot(face, cf);
			const double right = dot(face, cr);
			const double a = std::abs(std::atan2(right, fwd));
			int want = 0;
			if (a < PI_D * 0.125) {
				want = 1;
			} else if (a < PI_D * 0.375) {
				want = 3;
			} else if (a < PI_D * 0.625) {
				want = 2;
			} else if (a < PI_D * 0.875) {
				want = 4;
			}
			const int cur = view[i];
			if (want != cur) {
				if (a >= VIEW_LO[cur] - VIEW_HYST && a <= VIEW_HI[cur] + VIEW_HYST) {
					want = cur;
				} else if (view_t[i] > 0.0f) {
					want = cur;
				} else {
					view_t[i] = (float)VIEW_MIN;
				}
			}
			view[i] = (uint8_t)want;
			const double l = len(face);
			if (right < -FLIP_BAND * l) {
				flip[i] = 1;
			} else if (right > FLIP_BAND * l) {
				flip[i] = 0;
			}
		}
	} else {
		const double lenf = len(face);
		const double fx = face.x;
		if (fx < -FLIP_BAND * lenf) {
			flip[i] = 1;
		} else if (fx > FLIP_BAND * lenf) {
			flip[i] = 0;
		}
		if ((double)len2(face) > 0.04) {
			const double fc = dot(face, cf);
			const double fl = (double)len(face) * 0.2;
			if (fc > fl) {
				away[i] = 1;
			} else if (fc < -fl) {
				away[i] = 0;
			}
		}
	}
}

// The script's main loop over the crowd, from `start`, for every creature it can do whole; the first it cannot comes back
// as (i << 2) | code, and the script calls again from i + 1. The pool's end comes back as pool_max << 2.
int64_t CrowdCore::advance(int p_start, int p_boss, int p_flags) {
	const bool all_script = (p_flags & F_FREEZE) != 0;
	const bool watching = (p_flags & F_WATCH) != 0;
	const bool fleeing = (p_flags & F_FLEE) != 0;
	for (int i = p_start; i < pool_max; i++) {
		if (alive[i] == 0) {
			continue;
		}
		const int ti = type_idx[i];
		const int st = state[i];
		if (st == STATE_DYING) {
			// the script's whole dying tick unless it is only the frames, the body's sink and its slide on the sand: one in
			// the air, waiting on its blast or done goes back
			const float nt = (float)((double)timer[i] - delta);
			if (lift_h[i] > 0.0f || !(nt > 0.0f) || ((p_flags & F_CORPSE_AIR) != 0 && corpse_air.has(i)) || ((p_flags & F_BURST) != 0 && burst_bodies.has(i))) {
				n_dying_full++;
				return ((int64_t)i << 2) | CODE_FULL;
			}
			n_dying++;
			timer[i] = nt;
			anim_t[i] = (float)((double)anim_t[i] + delta * (double)t_die_fps[ti]);
			flash[i] = (float)dmax((double)flash[i] - delta * 6.0, 0.0);
			if ((double)nt < DIE_SINK) {
				squash[i] = (float)dmax((double)nt / DIE_SINK, 0.02);
			}
			// _corpse_tick on the ground
			V3 ck = kb[i];
			if ((double)len2(ck) < CORPSE_STOP * CORPSE_STOP) {
				kb[i] = V3{ 0.0f, 0.0f, 0.0f };
				continue;
			}
			V3 cp = clamp_arena(add(pos[i], mul(ck, (float)delta)));
			cp.y = (float)height_at(cp.x, cp.z);
			pos[i] = cp;
			const V3 ob = obst_push(cp, (double)radius[i]);
			if ((double)len2(ob) > 0.0) {
				const V3 n = norm(ob);
				const double into = dot(ck, n);
				if (into < 0.0) {
					ck = sub(ck, mul(n, (float)into));
				}
			}
			{
				const float w = (float)dclamp(delta * CORPSE_GROUND_DECAY, 0.0, 1.0);
				kb[i] = V3{ ck.x + (0.0f - ck.x) * w, ck.y + (0.0f - ck.y) * w, ck.z + (0.0f - ck.z) * w };
			}
			continue;
		}
		crowd_hp += (double)max_hp[i];
		crowd_n += 1;
		const bool poison_on = bool(poison_src[i]);
		if (poison_on) {
			poisoned += 1;
		}
		if (all_script || t_plain[ti] == 0 || st != STATE_MOVE || held[i] != 0 || hidden[i] != 0 || lift_t[i] > 0.0f || rise_t[i] < 1.0f || rise_v[i] != 0.0f || slow_t[i] > 0.0f || spin_t[i] > 0.0f ||
				(watching && onlook[i] == 1) || (fleeing && flee.has(i))) {
			n_full++;
			return ((int64_t)i << 2) | CODE_FULL;
		}
		if (lift_cd[i] > 0.0f) {
			lift_cd[i] = (float)((double)lift_cd[i] - delta);
		}
		flash[i] = (float)dmax((double)flash[i] - delta * 6.0, 0.0);
		{
			const double sq = squash[i];
			squash[i] = (float)(sq + (1.0 - sq) * (delta * 10.0));
		}
		const double ac = hamper_t[i] > 0.0f ? 1.0 - (double)hamper_f[i] : 1.0;
		contact_cd[i] = (float)dmax((double)contact_cd[i] - delta * ac, 0.0);
		cooldown[i] = (float)dmax((double)cooldown[i] - delta * ac, 0.0);
		if (hamper_t[i] > 0.0f) {
			hamper_t[i] = (float)dmax((double)hamper_t[i] - delta, 0.0);
		}
		if (status_t[i] > 0.0f) {
			status_t[i] = (float)dmax((double)status_t[i] - delta, 0.0);
		}
		if (shove_t[i] > 0.0f) {
			shove_t[i] = (float)((double)shove_t[i] - delta);
		}
		if (ign_t[i] > 0.0f) {
			ign_t[i] = (float)((double)ign_t[i] - delta);
		}
		if (view_t[i] > 0.0f) {
			view_t[i] = (float)((double)view_t[i] - delta);
		}
		if (steer_due(i, ti, p_boss)) {
			const double sdt_i = steer_dt(i);
			const double k = (far_push && sdt_i > sdt_base) ? sdt_base / sdt_i : 1.0;
			steer_plain(i, ti, sdt_i, k, poison_on);
		}
		// integrate
		const V3 v = add(mul(vel[i], wade_k[i]), kb[i]);
		{
			const float w = (float)(delta * 6.0);
			const V3 k = kb[i];
			kb[i] = V3{ k.x + (0.0f - k.x) * w, k.y + (0.0f - k.y) * w, k.z + (0.0f - k.z) * w };
		}
		V3 np = add(pos[i], mul(v, (float)delta));
		np = clamp_arena(np);
		np.y = (float)height_at(np.x, np.z);
		pos[i] = np;
		face_and_view(i, ti, v);
		if (poison_on || bool(fire_src[i])) {
			v_last = v;
			n_tail++;
			return ((int64_t)i << 2) | CODE_TAIL;
		}
		// the walk's clock
		const double run_fps = t_run_fps[ti];
		const double steps = (double)len(v) > 0.2 ? (run_fps > 0.0 ? run_fps : 10.0) * pace : ATTACK_FPS;
		anim_t[i] = (float)((double)anim_t[i] + delta * steps);
		// the bite: the script's own function deals it
		V3 d = sub(ppos, pos[i]);
		d.y = 0.0f;
		const double reach = (double)radius[i] + 0.45;
		if ((double)len2(d) < reach * reach && contact_cd[i] <= 0.0f && freeze_t[i] <= 0.0f && stun_t[i] <= 0.0f) {
			n_bite++;
			return ((int64_t)i << 2) | CODE_BITE;
		}
		n_plain++;
	}
	return (int64_t)pool_max << 2;
}

PackedFloat64Array CrowdCore::tick_stats() const {
	PackedFloat64Array out;
	out.resize(3);
	double *w = out.ptrw();
	w[0] = crowd_hp;
	w[1] = crowd_n;
	w[2] = poisoned;
	return out;
}

// The alive creatures whose type's flag is 1, in index order.
PackedInt32Array CrowdCore::alive_of_flag(const PackedByteArray &p_flags) const {
	PackedInt32Array out;
	const uint8_t *f = p_flags.ptr();
	int n = 0;
	for (int i = 0; i < pool_max; i++) {
		if (alive[i] == 1 && f[type_idx[i]] == 1) {
			n++;
		}
	}
	if (n > 0) {
		out.resize(n);
		int32_t *w = out.ptrw();
		int k = 0;
		for (int i = 0; i < pool_max; i++) {
			if (alive[i] == 1 && f[type_idx[i]] == 1) {
				w[k++] = i;
			}
		}
	}
	return out;
}

PackedInt64Array CrowdCore::pass_counts() const {
	PackedInt64Array out;
	out.resize(6);
	int64_t *w = out.ptrw();
	w[0] = n_plain;
	w[1] = n_dying;
	w[2] = n_full;
	w[3] = n_tail;
	w[4] = n_bite;
	w[5] = n_dying_full;
	return out;
}

Vector3 CrowdCore::last_v() const {
	return Vector3(v_last.x, v_last.y, v_last.z);
}

// refresh_drawn with _vis_bounds_into inline: half the crowd by parity (-1 all). The bounds pass through floats on their way
// out of _vb in the script, so they do here.
void CrowdCore::refresh_drawn(const PackedFloat32Array &p_planes, const Vector3 &p_cam_up, const Vector3 &p_cpos, const Vector3 &p_scf, double p_look_s, double p_cam_b, double p_cam_t, double p_badge, int p_parity) {
	const float *pf = p_planes.ptr();
	const V3 cam_up{ p_cam_up.x, p_cam_up.y, p_cam_up.z };
	const V3 scf{ p_scf.x, p_scf.y, p_scf.z };
	const double cpx = p_cpos.x, cpy = p_cpos.y, cpz = p_cpos.z;
	const int step = p_parity < 0 ? 1 : 2;
	for (int i = 0; i < pool_max; i++) {
		if (alive[i] == 0 || (p_parity >= 0 && (i & 1) != p_parity)) {
			continue;
		}
		const int t = type_idx[i];
		const double s = size[i];
		const int cv = t * CV_N;
		const double sq_hi = dmax(dmax((double)squash[i], 1.0 + 1.6 * (double)t_cv[cv + 1]), VIS_STRETCH) * 1.05 + 0.05;
		const int sb = t * 4;
		const double drop = std::abs((double)t_sh[sb + 3]) + std::abs((double)t_ddrop[t]);
		double lo = -s * sq_hi * drop;
		double hi = s * sq_hi * (1.0 + drop);
		double half_w = 0.7 * s;
		double head = 1.0;
		const bool rising = rise_t[i] < 1.0f;
		if (rising || t_badge[t] != 0) {
			head = dmax(t_head[t], 1.0);
		}
		if (rising) {
			lo -= s * sq_hi * head;
		}
		if (t_badge[t] != 0) {
			hi = dmax(hi, s * head * sq_hi + 0.12 + p_badge * 1.1);
			half_w = dmax(half_w, p_badge * 0.75);
		}
		const double mid = (lo + hi) * 0.5;
		const double hh = (hi - lo) * 0.5;
		double r = std::sqrt(half_w * half_w + hh * hh);
		const double roll = std::abs((double)t_cv[cv + 3]) + (t_cv[cv] > 0.0f ? ROCK : 0.0);
		if (roll > 0.0) {
			const double far = dmax(std::abs(lo), std::abs(hi));
			r += roll * std::sqrt(half_w * half_w + far * far);
		}
		r += (double)t_cv[cv] + BOUNCE * s;
		const V3 c = add(add(pos[i], V3{ 0.0f, lift_h[i], 0.0f }), mul(cam_up, (float)mid));
		const V3 sc = add(pos[i], mul(scf, (float)((double)t_sh[sb + 2] * s)));
		const double cx = c.x, cy = c.y, cz = c.z;
		double rr = (double)(float)r;
		const double sx = (double)sc.x - cx;
		const double sy = (double)sc.y - cy;
		const double sz = (double)sc.z - cz;
		const float sr = (float)(s * (0.275 * std::abs((double)t_sh[sb]) + 0.17 * std::abs((double)t_sh[sb + 1])) + 0.3);
		const double rs = std::sqrt(sx * sx + sy * sy + sz * sz) + (double)sr;
		if (rs > rr) {
			rr = rs;
		}
		const double ex = cx - cpx;
		const double ey = cy - cpy;
		const double ez = cz - cpz;
		rr += VIS_BORDER_M + (double)len(add(vel[i], kb[i])) * p_look_s + p_cam_b + p_cam_t * std::sqrt(ex * ex + ey * ey + ez * ez);
		bool seen = true;
		for (int k = 0; k < 20; k += 4) {
			if ((double)pf[k] * cx + (double)pf[k + 1] * cy + (double)pf[k + 2] * cz - (double)pf[k + 3] > rr) {
				seen = false;
				break;
			}
		}
		if (seen) {
			drawn_vis[i] = 1;
			vis_hold[i] = VIS_HOLD;
		} else if (vis_hold[i] > step) {
			vis_hold[i] = (uint8_t)(vis_hold[i] - step);
		} else {
			vis_hold[i] = 0;
			drawn_vis[i] = 0;
		}
	}
}
