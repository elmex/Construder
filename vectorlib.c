/*
 * Games::Construder - A 3D Game written in Perl with an infinite and modifiable world.
 * Copyright (C) 2011  Robin Redeker
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#ifndef VECTORLIB_C
#define VECTORLIB_C 1
#include <stdio.h>
#include <math.h>

#define SWAP(type,a,b) do { type tmp = b; b = a; a = b; } while (0)

#define vec3_init(vname,a,b,c) double vname[3]; vname[0] = a; vname[1] = b; vname[2] = c;
#define vec3_clone(vname,vd)   vec3_init(vname,vd[0],vd[1],vd[2])
#define vec3_assign(v1,v2)     v1[0] = v2[0]; v1[1] = v2[1]; v1[2] = v2[2];
#define vec3_add(v1,v2)        v1[0] += v2[0]; v1[1] += v2[1]; v1[2] += v2[2];
#define vec3_sub(v1,v2)        v1[0] -= v2[0]; v1[1] -= v2[1]; v1[2] -= v2[2];
#define vec3_s_div(v1,s)       v1[0] /= (double) s; v1[1] /= (double) s; v1[2] /= (double) s;
#define vec3_s_mul(v1,s)       v1[0] *= (double) s; v1[1] *= (double) s; v1[2] *= (double) s;
#define vec3_dot(v1,v2)        (v1[0] * v2[0] + v1[1] * v2[1] + v1[2] * v2[2])
#define vec3_len(v)            sqrt (vec3_dot (v, v))
#define vec3_norm(v)           vec3_s_div (v, vec3_len (v))
#define vec3_floor(v)          v[0] = floor (v[0]); v[1] = floor (v[1]); v[2] = floor (v[2]);

#endif
