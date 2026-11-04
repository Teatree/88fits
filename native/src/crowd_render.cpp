// Pass 125: EnemyManager._render for the creatures in a plain state: one float row per instance in a buffer per type, handed
// to the rendering server whole, instead of three engine calls for each creature a frame. It decides nothing the rules
// read (only pictures), and what it cannot draw (a wind-up, a charge's carriage, an attack strip with its own frames, a badge
// over a head, a shadow by the water) it reserves a slot for and lists: the script's _draw_one fills that slot (put_instance,
// put_shadow). Row layout: rendering server's MultiMesh buffer, 3x4 transform by rows, then colour, then custom data.
#include "crowd_core.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/quaternion.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

namespace {

const int STATE_MOVE = 0;
const int STATE_WINDUP = 1;
const int STATE_CHARGE = 2;
const int STATE_DYING = 3;
const int STATE_ATTACK = 4;
const int STATE_SPAWN = 5;
const int A_RUN = 0;
const int A_IDLE = 1;
const int A_ATTACK = 2;
const int A_HIT = 3;
const int A_DIE = 4;
const int A_LEFT0 = 13;
const int N_ANIMS = 19;
const int VIEW_ANIM[2][5] = { { 0, 5, 7, 9, 11 }, { 1, 6, 8, 10, 12 } };
const int LEFT_OF[7] = { 13, 14, 15, 16, -1, 17, 18 };
const double RISE_FLAG = 0.5;
const double SPECIAL_GLOW_STEP = 64.0;
const double SHADOW_CACHE_MOVE = 0.08;
const double SHADOW_LIFT = 0.03;

inline V3 add(V3 a, V3 b) { return V3{ a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V3 sub(V3 a, V3 b) { return V3{ a.x - b.x, a.y - b.y, a.z - b.z }; }
inline V3 mul(V3 a, float s) { return V3{ a.x * s, a.y * s, a.z * s }; }
inline float len2(V3 a) { return a.x * a.x + a.y * a.y + a.z * a.z; }
inline double dmax(double a, double b) { return a < b ? b : a; }
inline double dclamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }

template <typename T>
inline T *wptr(const T *p) { return const_cast<T *>(p); }

} // namespace

void CrowdCore::set_type_mm(int p_t, const RID &p_mm) {
	if ((int)tdraw.size() <= p_t) {
		tdraw.resize(p_t + 1);
	}
	tdraw[p_t].mm = p_mm;
}

// The draw's pass over the crowd; bind ran just before. Fills the buffers for what it can and lists the rest. The number of
// creatures it reserved for the script comes back; render_escapes has them, render_counts the types' counts.
int64_t CrowdCore::render(const Array &a, const PackedFloat64Array &p_s) {
	int q = 0;
	const PackedInt32Array p_off = a[q++];
	const PackedInt32Array p_cnt = a[q++];
	const PackedByteArray p_ok = a[q++];
	const PackedByteArray p_okb = a[q++];
	const PackedByteArray p_hit = a[q++];
	const PackedByteArray p_lsets = a[q++];
	const PackedByteArray p_fix = a[q++];
	const PackedByteArray p_atkv = a[q++];
	const PackedByteArray p_throw = a[q++];
	const PackedByteArray p_squad = a[q++];
	const PackedColorArray p_vtint = a[q++];
	const PackedColorArray p_stint = a[q++];
	const PackedColorArray p_elite = a[q++];
	const PackedByteArray p_blue = a[q++];
	const PackedByteArray p_green = a[q++];
	const PackedFloat32Array p_vglow = a[q++];
	const PackedFloat32Array p_lakes = a[q++];
	const PackedFloat32Array p_fr = a[q++];
	const int32_t *t_off = p_off.ptr();
	const int32_t *t_cnt = p_cnt.ptr();
	const uint8_t *t_ok = p_ok.ptr();
	const uint8_t *t_okb = p_okb.ptr();
	const uint8_t *t_hit = p_hit.ptr();
	const uint8_t *t_lsets = p_lsets.ptr();
	const uint8_t *t_fix = p_fix.ptr();
	const uint8_t *t_atkv = p_atkv.ptr();
	const uint8_t *t_throw = p_throw.ptr();
	const uint8_t *t_squad = p_squad.ptr();
	const Color *vtint = p_vtint.ptr();
	const Color *stint = p_stint.ptr();
	const Color *elite = p_elite.ptr();
	const uint8_t *fire_blue = p_blue.ptr();
	const uint8_t *flash_green = p_green.ptr();
	const float *vglow = p_vglow.ptr();
	const float *lakes = p_lakes.ptr();
	const int n_lakes = p_lakes.size() / 3;
	const float *fr = p_fr.ptr();

	const double *s0 = p_s.ptr();
	int k0 = 0;
	const V3 scf{ (float)s0[k0], (float)s0[k0 + 1], (float)s0[k0 + 2] };
	k0 += 3;
	const V3 cam_up{ (float)s0[k0], (float)s0[k0 + 1], (float)s0[k0 + 2] };
	k0 += 3;
	const V3 hero{ (float)s0[k0], (float)s0[k0 + 1], (float)s0[k0 + 2] };
	k0 += 3;
	const bool shadow_all = s0[k0++] != 0.0;
	const double shadow_r2 = s0[k0++];
	const bool has_eye = s0[k0++] != 0.0;
	const int bounty_i = (int)s0[k0++];
	const int tethered_i = (int)s0[k0++];
	const double glow_clock = s0[k0++];
	const bool lake = s0[k0++] != 0.0;
	const int n_types = (int)s0[k0++];
	hmode = (int)s0[k0++];
	size_m = s0[k0++];
	resolution = s0[k0++];
	grid_n = (int)s0[k0++];
	const V3 scr{ -scf.z, 0.0f, scf.x };

	if ((int)tdraw.size() < n_types) {
		tdraw.resize(n_types);
	}
	const int row_n = pool_max * 20;
	for (int t = 0; t < n_types; t++) {
		TypeDraw &td = tdraw[t];
		if (td.buf.size() != row_n) {
			td.buf.resize(row_n);
		}
		td.count = 0;
	}
	if (shadow_buf.size() != pool_max * 12) {
		shadow_buf.resize(pool_max * 12);
	}
	float *sh_w = shadow_buf.ptrw();
	shadow_n = 0;
	escapes.clear();
	// the draped shadows' cache
	if ((int)g_shc.at.size() != pool_max) {
		g_shc.at.assign(pool_max, V3{ 0, 0, 0 });
		g_shc.type.assign(pool_max, -1.0f);
		g_shc.shs.assign(pool_max, 0.0f);
		g_shc.row.assign((size_t)pool_max * 12, 0.0f);
	}
	{
		const float e = 0.00001f;
		if (std::abs(scf.x - g_shc.cf.x) > e || std::abs(scf.y - g_shc.cf.y) > e || std::abs(scf.z - g_shc.cf.z) > e) {
			g_shc.cf = scf;
			std::fill(g_shc.type.begin(), g_shc.type.end(), -1.0f);
		}
	}
	// the pointers of the type buffers, taken once a frame (unique: only an upload shares them, and only within its call)
	std::vector<float *> bufs(n_types);
	for (int t = 0; t < n_types; t++) {
		bufs[t] = tdraw[t].buf.ptrw();
	}

	for (int i = 0; i < pool_max; i++) {
		if (alive[i] == 0 || hidden[i] == 1 || drawn_vis[i] == 0) {
			continue;
		}
		const int t = type_idx[i];
		TypeDraw &td = tdraw[t];
		const int st = state[i];
		const int k = td.count;
		// what the script draws: everything about these is in its _draw_one
		bool script_one = st == STATE_WINDUP || st == STATE_CHARGE || t_badge[t] != 0 || i == tethered_i || held[i] == 1;
		int strip = 0;
		if (!script_one) {
			// _strip_of
			const V3 mv = t_faces[t] == 1 ? intent[i] : vel[i];
			const int move = (st == STATE_SPAWN || (double)len2(mv) < 0.04) ? A_IDLE : A_RUN;
			int a0 = move;
			if (st == STATE_DYING) {
				a0 = A_DIE;
			} else if (st == STATE_ATTACK) {
				a0 = A_ATTACK;
				if (t_atkv[t] == 1 || t_throw[t] == 1 || t_squad[t] == 1) {
					script_one = true;
				}
			}
			if (!script_one && (double)flash[i] > 0.6 && t_hit[t] == 1 && st != STATE_DYING) {
				a0 = A_HIT;
			}
			if (!script_one) {
				if (t_eight[t] == 1) {
					if ((a0 == A_HIT || a0 == A_ATTACK) && view[i] != 0) {
						a0 = move;
					}
					strip = a0;
					if (a0 == A_RUN || a0 == A_IDLE) {
						const int cand = VIEW_ANIM[a0][view[i]];
						if (t_ok[t * N_ANIMS + cand] == 1) {
							strip = cand;
						}
					}
				} else if (away[i] == 1 && (a0 == A_RUN || a0 == A_IDLE) && t_okb[t * 2 + a0] == 1) {
					strip = a0 == A_RUN ? 5 : 6;
				} else {
					strip = a0;
				}
				if (strip == A_ATTACK && (t_atkv[t] == 1 || t_throw[t] == 1 || t_squad[t] == 1)) {
					script_one = true;
				}
			}
		}
		td.count = k + 1;
		if (script_one) {
			escapes.push_back(i);
			escapes.push_back(k);
			continue;
		}
		// _lr_strip
		int shown = strip;
		if (t_lsets[t] != 0 && flip[i] != 0 && strip >= 0 && strip < 7) {
			const int l = LEFT_OF[strip];
			if (l >= 0 && t_cnt[t * N_ANIMS + l] > 0 && t_ok[t * N_ANIMS + l] != 0) {
				shown = l;
			}
		}
		const int n = t_cnt[t * N_ANIMS + shown];
		const int ai = (int)anim_t[i];
		const int frame = t_off[t * N_ANIMS + shown] + (strip == A_DIE ? (ai < n - 1 ? ai : n - 1) : (ai % (n > 1 ? n : 1)));
		const double s = size[i];
		double sq = squash[i];
		if (strip == A_RUN) {
			sq += std::sin((double)anim_t[i] * 1.5) * 0.05;
		}
		const double drop = t_sh[t * 4 + 3];
		V3 at{ pos[i].x, pos[i].y + lift_h[i], pos[i].z };
		const double sqm = dmax(sq, 0.2);
		if (drop != 0.0) {
			at = sub(at, mul(cam_up, (float)(drop * s * sqm)));
		}
		if (strip == A_DIE && t_ddrop[t] != 0.0f) {
			const double dd = t_ddrop[t];
			const double kk = dclamp((double)(ai < n - 1 ? ai : n - 1) / (double)(n - 1 > 1 ? n - 1 : 1), 0.0, 1.0);
			at = sub(at, mul(cam_up, (float)(dd < 0.0 ? dd * kk * s : dd * kk * s * sqm)));
		}
		const double rise = rise_t[i];
		const bool rising = rise < 1.0;
		const double r = dclamp(rise, 0.0, 1.0);
		const double rise_k = 1.0 - (1.0 - r) * (1.0 - r);
		if (rising) {
			at = sub(at, mul(cam_up, (float)((1.0 - rise_k) * s * t_head[t] * sqm)));
		}
		float *row = bufs[t] + (size_t)k * 20;
		const float fs = (float)s;
		row[0] = fs;
		row[1] = 0.0f;
		row[2] = 0.0f;
		row[3] = at.x;
		row[4] = 0.0f;
		row[5] = fs;
		row[6] = rising ? (float)dclamp((double)t_sh[t * 4 + 3] + (1.0 - rise_k) * t_head[t], 0.0, 1.0) : 0.0f;
		row[7] = at.y;
		row[8] = 0.0f;
		row[9] = 0.0f;
		row[10] = fs;
		row[11] = at.z;
		// tint_of
		Color tint = vtint[i];
		if (elite_idx[i] >= 0) {
			const Color &e = elite[elite_idx[i]];
			tint = Color(e.r, e.g, e.b, 0.7f);
		}
		if (bool(fire_src[i])) {
			const double fl = std::abs(std::sin((double)anim_t[i] * 5.0 + (double)i));
			if (fire_blue[i] == 1) {
				tint = Color(0.25f, (float)(0.55 + 0.12 * fl), 1.0f, 1.0f);
			} else {
				tint = Color(1.0f, (float)(0.18 + 0.22 * fl), 0.02f, 1.0f);
			}
		} else if (bool(poison_src[i])) {
			tint = Color(0.45f, 1.0f, 0.3f, 0.8f);
		}
		if (status_t[i] > 0.0f) {
			tint = stint[i];
		}
		if (freeze_t[i] > 0.0f) {
			tint = Color(0.2f, 0.5f, 1.0f, 1.0f);
		}
		row[12] = tint.r;
		row[13] = tint.g;
		row[14] = tint.b;
		row[15] = tint.a;
		// the flash, the mirror bit, the rim
		double fl = flash[i];
		if (i == bounty_i && fl < 0.4) {
			fl = 0.4 + 0.25 * std::sin(glow_clock * 3.0);
			flash_hot[i] = 1;
		}
		if (flash_green[i] == 1) {
			fl = -fl;
		} else if (flash_hot[i] == 1) {
			fl = 2.0 + fl;
		}
		double fy = flip[i];
		if (t_lsets[t] == 1 && (strip < 7 || strip >= A_LEFT0)) {
			fy = 0.0;
		} else {
			const int fix = t_fix[t * 2 + ((strip == 5 || strip == 6) ? 1 : 0)];
			if (fix == 1) {
				fy = 1.0 - fy;
			} else if (fix == 2) {
				fy = 0.0;
			}
		}
		if (vglow[i] > 0.0f && st != STATE_DYING) {
			fy += SPECIAL_GLOW_STEP * std::round(dclamp((double)vglow[i], 0.0, 1.0) * 16.0);
		}
		row[16] = (float)((double)frame + (rising ? RISE_FLAG : 0.0));
		row[17] = (float)fy;
		row[18] = (float)fl;
		row[19] = (float)sq;
		// the shadow
		bool wants = shadow_all;
		if (!wants) {
			const V3 dh = sub(hero, pos[i]);
			wants = (double)len2(dh) < shadow_r2;
		}
		if (!wants && has_eye) {
			wants = true;
			const V3 p = pos[i];
			for (int pl = 0; pl < 24; pl += 4) {
				if (fr[pl] * p.x + fr[pl + 1] * p.y + fr[pl + 2] * p.z > fr[pl + 3]) {
					wants = false;
					break;
				}
			}
		}
		if (!wants) {
			continue;
		}
		// by the water the script decides (shadow_wet): k = -1 asks it for the shadow alone
		if (lake) {
			bool near_water = false;
			for (int l = 0; l < n_lakes; l++) {
				const double dx = (double)pos[i].x - (double)lakes[l * 3];
				const double dz = (double)pos[i].z - (double)lakes[l * 3 + 1];
				if (dx * dx + dz * dz < (double)lakes[l * 3 + 2]) {
					near_water = true;
					break;
				}
			}
			if (near_water) {
				escapes.push_back(i);
				escapes.push_back(-1);
				continue;
			}
		}
		// _shadow_xform_cached
		const double shs = s / (1.0 + (double)lift_h[i] * 0.5);
		float *cached = g_shc.row.data() + (size_t)i * 12;
		const V3 moved = sub(g_shc.at[i], pos[i]);
		const bool hit = g_shc.type[i] == (float)t && std::abs((double)g_shc.shs[i] - shs) < 0.002 && (double)len2(moved) < SHADOW_CACHE_MOVE * SHADOW_CACHE_MOVE;
		if (!hit) {
			const int sb = t * 4;
			V3 o = pos[i];
			const double up = (double)t_sh[sb + 2] * s;
			if (up != 0.0) {
				o = add(o, mul(scf, (float)up));
				o.y = (float)height_at(o.x, o.z);
			}
			const V3 bx = mul(scr, (float)(shs * 0.55 * (double)t_sh[sb]));
			const V3 bz = mul(V3{ -scf.x, -scf.y, -scf.z }, (float)(shs * 0.34 * (double)t_sh[sb + 1]));
			// drape
			Basis basis(Vector3(bx.x, bx.y, bx.z), Vector3(0, 1, 0), Vector3(bz.x, bz.y, bz.z));
			Vector3 origin(o.x, o.y, o.z);
			if (hmode == 0) {
				origin.y += (float)SHADOW_LIFT;
			} else {
				const float ax_x = bx.x * 0.5f, ax_z = bx.z * 0.5f, az_x = bz.x * 0.5f, az_z = bz.z * 0.5f;
				if (ax_x * ax_x + ax_z * ax_z < 0.0001f || az_x * az_x + az_z * az_z < 0.0001f) {
					origin.y = (float)(height_at(o.x, o.z) + SHADOW_LIFT);
				} else {
					const double hxp = height_at((double)o.x + ax_x, (double)o.z + ax_z);
					const double hxm = height_at((double)o.x - ax_x, (double)o.z - ax_z);
					const double hzp = height_at((double)o.x + az_x, (double)o.z + az_z);
					const double hzm = height_at((double)o.x - az_x, (double)o.z - az_z);
					const double hc = height_at(o.x, o.z);
					const Vector3 tx(ax_x * 2.0f, (float)(hxp - hxm), ax_z * 2.0f);
					const Vector3 tz(az_x * 2.0f, (float)(hzp - hzm), az_z * 2.0f);
					Vector3 nrm = tz.cross(tx).normalized();
					if (nrm.y < 0.0f) {
						nrm = -nrm;
					}
					const double base = 0.25 * (hxp + hxm + hzp + hzm);
					const double dx2 = hxp + hxm - 2.0 * hc;
					const double dz2 = hzp + hzm - 2.0 * hc;
					const double over = (std::abs(dx2) + std::abs(dz2)) * 0.5;
					const double ny = dmax((double)nrm.y, 0.3);
					origin = Vector3(o.x, (float)base, o.z) + Vector3(0, (float)(over / ny + SHADOW_LIFT), 0);
					const Vector3 up_v = nrm.length_squared() > 0.0001f ? nrm.normalized() : Vector3(0, 1, 0);
					if (!up_v.is_equal_approx(Vector3(0, 1, 0))) {
						basis = Basis(Quaternion(Vector3(0, 1, 0), up_v)) * basis;
					}
				}
			}
			cached[0] = basis.rows[0][0];
			cached[1] = basis.rows[0][1];
			cached[2] = basis.rows[0][2];
			cached[3] = origin.x;
			cached[4] = basis.rows[1][0];
			cached[5] = basis.rows[1][1];
			cached[6] = basis.rows[1][2];
			cached[7] = origin.y;
			cached[8] = basis.rows[2][0];
			cached[9] = basis.rows[2][1];
			cached[10] = basis.rows[2][2];
			cached[11] = origin.z;
			g_shc.at[i] = pos[i];
			g_shc.type[i] = (float)t;
			g_shc.shs[i] = (float)shs;
		}
		float *sr = sh_w + (size_t)shadow_n * 12;
		if (rising) {
			const float sk = (float)(0.35 + (1.0 - 0.35) * rise_k);
			sr[0] = cached[0] * sk;
			sr[1] = cached[1] * sk;
			sr[2] = cached[2] * sk;
			sr[3] = cached[3];
			sr[4] = cached[4];
			sr[5] = cached[5];
			sr[6] = cached[6];
			sr[7] = cached[7];
			sr[8] = cached[8] * sk;
			sr[9] = cached[9] * sk;
			sr[10] = cached[10] * sk;
			sr[11] = cached[11];
		} else {
			std::memcpy(sr, cached, sizeof(float) * 12);
		}
		shadow_n++;
	}
	return (int64_t)escapes.size() / 2;
}

PackedInt32Array CrowdCore::render_escapes() const {
	PackedInt32Array out;
	out.resize((int64_t)escapes.size());
	if (!escapes.empty()) {
		std::memcpy(out.ptrw(), escapes.data(), escapes.size() * sizeof(int32_t));
	}
	return out;
}

PackedInt32Array CrowdCore::render_counts() const {
	PackedInt32Array out;
	out.resize((int64_t)tdraw.size());
	int32_t *w = out.ptrw();
	for (size_t t = 0; t < tdraw.size(); t++) {
		w[t] = tdraw[t].count;
	}
	return out;
}

// One row (20 floats) the script worked out for a creature whose slot render reserved.
void CrowdCore::put_instance(int p_t, int p_k, const PackedFloat32Array &p_row) {
	if (p_t < 0 || p_t >= (int)tdraw.size() || p_k < 0 || p_row.size() != 20) {
		return;
	}
	std::memcpy(tdraw[p_t].buf.ptrw() + (size_t)p_k * 20, p_row.ptr(), sizeof(float) * 20);
}

// One shadow (12 floats) from the script: at the next free slot.
void CrowdCore::put_shadow(int p_k, const PackedFloat32Array &p_row) {
	if (p_row.size() != 12 || shadow_n >= pool_max) {
		return;
	}
	std::memcpy(shadow_buf.ptrw() + (size_t)shadow_n * 12, p_row.ptr(), sizeof(float) * 12);
	shadow_n++;
}

int CrowdCore::render_shadow_n() const {
	return shadow_n;
}

int CrowdCore::render_reserve_shadow() {
	return shadow_n;
}

// Every shadow draped afresh on the next draw (the pixel proof: the script's cache and this one last draped at other moments).
void CrowdCore::shadow_cache_clear() {
	std::fill(g_shc.type.begin(), g_shc.type.end(), -1.0f);
}

// The buffers of the types drawn this frame or the last go to the server. Each instance's rows are copied by the server in
// the renderer's own packing; an unused type is not touched.
void CrowdCore::render_finish(const RID &p_shadow_mm, int p_shadow_n, int p_warm) {
	RenderingServer *rs = RenderingServer::get_singleton();
	for (size_t t = 0; t < tdraw.size(); t++) {
		TypeDraw &td = tdraw[t];
		if (td.count > 0 && td.mm.is_valid()) {
			rs->multimesh_set_buffer(td.mm, td.buf);
		}
		td.last = td.count;
	}
	if (shadow_n > 0 && p_shadow_mm.is_valid()) {
		rs->multimesh_set_buffer(p_shadow_mm, shadow_buf);
	}
	last_shadow = shadow_n;
}
