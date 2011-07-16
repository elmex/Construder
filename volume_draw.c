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
/* This file contains the volume/voxel drawing library that is used
 * to "draw" the sector types.
 *
 * A set of 4 buffers is used to draw the sector types. Those buffers
 * can be blended into each other and every operation done on a cell
 * can also be blended with the value from the selected "source" buffer.
 */

#include <math.h>
#include "vectorlib.c"
#include "noise_3d.c"

typedef struct _vol_draw_ctx {
  unsigned int size;
  double      *buffers[4];
  double      *src;  // "source" buffer for drawing operations.
  double      *dst;  // destination buffer of drawing operations.

  unsigned int draw_op;

  /* Destination range of drawing operations.
   * Cells with a value outside this range are not changed.
   */
  double  dst_range[2];

  /* The source range determines that only the voxels that are
   * inside this range in the source buffer are drawn to the destination.
   * If a cell in the source buffer is outside this range the
   * drawing operation is inhibited, regardless of the src_blend value.
   */
  double  src_range[2];

  // How much of the source buffer is used in drawing operations.
  double  src_blend;

#define VOL_DRAW_ADD 1
#define VOL_DRAW_SUB 2
#define VOL_DRAW_MUL 3
#define VOL_DRAW_SET 4

} vol_draw_ctx;

#define DRAW_DST(x,y,z) DRAW_CTX.dst[((unsigned int) (x)) + ((unsigned int) (y)) * DRAW_CTX.size + ((unsigned int) (z)) * (DRAW_CTX.size * DRAW_CTX.size)]
#define DRAW_SRC(x,y,z) DRAW_CTX.src[((unsigned int) (x)) + ((unsigned int) (y)) * DRAW_CTX.size + ((unsigned int) (z)) * (DRAW_CTX.size * DRAW_CTX.size)]

static vol_draw_ctx DRAW_CTX;

void vol_draw_init ()
{
  DRAW_CTX.src  = 0;
  DRAW_CTX.buffers[0] = 0;
  DRAW_CTX.buffers[1] = 0;
  DRAW_CTX.buffers[2] = 0;
  DRAW_CTX.buffers[3] = 0;
  DRAW_CTX.dst  = 0;
  DRAW_CTX.size = 0;
  DRAW_CTX.draw_op = 0;
  DRAW_CTX.dst_range[0] = 0;
  DRAW_CTX.dst_range[1] = 1;
  DRAW_CTX.src_range[0] = 0;
  DRAW_CTX.src_range[1] = 1;
  DRAW_CTX.src_blend = 0;
}

void vol_draw_set_dst_range (double a, double b)
{
  DRAW_CTX.dst_range[0] = a;
  DRAW_CTX.dst_range[1] = b;
}

void vol_draw_set_src_range (double a, double b)
{
  DRAW_CTX.src_range[0] = a;
  DRAW_CTX.src_range[1] = b;
}

void vol_draw_set_src_blend (double r)
{
  DRAW_CTX.src_blend = r;
}

void vol_draw_set_dst (unsigned int i)
{
  if (i > 3)
    i = 3;

  DRAW_CTX.dst = DRAW_CTX.buffers[i];
}

void vol_draw_set_src (unsigned int i)
{
  if (i > 3)
    i = 3;

  DRAW_CTX.src = DRAW_CTX.buffers[i];
}

void vol_draw_set_op (unsigned int op)
{
  DRAW_CTX.draw_op = op;
}

void vol_draw_alloc (unsigned int size)
{
  int i;
  if (DRAW_CTX.buffers[0])
    {
      for (i = 0; i < 4; i++)
        safefree (DRAW_CTX.buffers[i]);
    }

  for (i = 0; i < 4; i++)
    {
      DRAW_CTX.buffers[i] = safemalloc (sizeof (double) * size * size * size);
      memset (DRAW_CTX.buffers[i], 0, sizeof (double) * size * size * size);
    }

  DRAW_CTX.size = size;

  vol_draw_set_src (0);
  vol_draw_set_dst (1);

  vol_draw_set_dst_range (0, 1);
  vol_draw_set_src_range (0, 1);

  vol_draw_set_src_blend (1);

  vol_draw_set_op (VOL_DRAW_SET);
}

double linerp (double a, double b, double x)
{
   return a * (1 - x) + b * x;
}

void vol_draw_op (unsigned int x, unsigned int y, unsigned int z, double val)
{
  if (x >= DRAW_CTX.size
      || y >= DRAW_CTX.size
      || z >= DRAW_CTX.size)
    return;


  if (DRAW_DST(x,y,z) < DRAW_CTX.dst_range[0]
      || DRAW_DST(x,y,z) > DRAW_CTX.dst_range[1])
    return;

  if (DRAW_SRC(x,y,z) < DRAW_CTX.src_range[0]
      || DRAW_SRC(x,y,z) > DRAW_CTX.src_range[1])
    return;

  double src = DRAW_SRC(x, y, z);
  if (DRAW_CTX.src_blend < 0)
    {
      val = 1 - val;
      val = linerp (val, src, -DRAW_CTX.src_blend);
    }
  else
    {
      val = linerp (val, src, DRAW_CTX.src_blend);
    }

  switch (DRAW_CTX.draw_op)
    {
      case VOL_DRAW_ADD:
        DRAW_DST(x,y,z) += val;
        break;

      case VOL_DRAW_SUB:
        DRAW_DST(x,y,z) -= val;
        if (DRAW_DST(x,y,z) < 0)
          DRAW_DST(x,y,z) = 0;
        break;

      case VOL_DRAW_MUL: DRAW_DST(x,y,z) *= val; break;
      case VOL_DRAW_SET: DRAW_DST(x,y,z) = val; break;
    }
}

void vol_draw_val (double val)
{
  int x, y, z;
  for (z = 0; z < DRAW_CTX.size; z++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (x = 0; x < DRAW_CTX.size; x++)
        vol_draw_op (x, y, z, val);
}

void vol_draw_dst_self ()
{
  int x, y, z;
  for (z = 0; z < DRAW_CTX.size; z++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (x = 0; x < DRAW_CTX.size; x++)
        vol_draw_op (x, y, z, DRAW_DST (x, y, z));
}

void vol_draw_map_range (float a, float b, float j, float k)
{
  if (a > b)
    {
      double l = a;
      a = b;
      b = a;
    }

  double range = b - a;
  if (range <= 0.00001)
    range = 1;

  int x, y, z;
  for (z = 0; z < DRAW_CTX.size; z++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (x = 0; x < DRAW_CTX.size; x++)
        {
          double v = DRAW_DST(x, y, z);
          if (v >= a && v <= b)
            {
              v -= a;
              v /= range;
              DRAW_DST(x, y, z) = linerp (j, k, v);
            }
        }
}

void vol_draw_histogram_equalize (int buckets, double a, double b)
{
  int eq[buckets];
  int lkup[buckets];
  memset (eq, 0, sizeof (int) * buckets);
  memset (lkup, 0, sizeof (int) * buckets);

  int x, y, z;
  for (x = 0; x < DRAW_CTX.size; x++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (z = 0; z < DRAW_CTX.size; z++)
        {
          double v = DRAW_DST (x, y, z);

          if (v < a || v > b)
            continue;
          v = linerp (0, 1, (v - a) / (b - a));

          int bket = floor (v * (double) buckets);
          eq[bket]++;
        }

  int i;
  int sum = 0;
  for (i = 0; i < buckets; i++)
    {
      sum += eq[i];
      lkup[i] = sum;
      //d// printf ("XX %d, %d => %d [%d]\n", i, eq[i], lkup[i], sum);
    }

  for (x = 0; x < DRAW_CTX.size; x++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (z = 0; z < DRAW_CTX.size; z++)
        {
          double v = DRAW_DST (x, y, z);

          if (v < a || v > b)
            continue;
          v = linerp (0, 1, (v - a) / (b - a));

          int bket = floor (v * (double) buckets);
          int lk = lkup[bket];
          DRAW_DST (x, y, z) = (double) lk / (double) sum;
        }
}

static void draw_3d_line_bresenham (int x0, int y0, int z0, int x1, int y1, int z1)
{
  int x_inc = (x1 > x0) ? +1 : -1,
      y_inc = (y1 > y0) ? +1 : -1,
      z_inc = (z1 > z0) ? +1 : -1;

  int dx = abs (x1 - x0),
      dy = abs (y1 - y0),
      dz = abs (z1 - z0);

  int d1 = 2 * dy - dx,
      d2 = 2 * dz - dx;

  int inc_e1  = 2 * dy,
      inc_ne1 = 2 * (dy - dx),
      inc_e2  = 2 * dz,
      inc_ne2 = 2 * (dz - dx);

  while (x0 != x1) {
    vol_draw_op (x0, y0, z0, 1);

    if (d1 <= 0)
      d1 += inc_e1;
    else
      {
        y0 += y_inc;
        d1 += inc_ne1;
      }

    if (d2 <= 0)
      d2 += inc_e2;
    else
      {
        z0 += z_inc;
        d2 += inc_ne2;
      }

    x0 += x_inc;
  }
  vol_draw_op (x0, y0, z0, 1);
}

static void draw_3d_line (int x0, int y0, int z0, int x1, int y1, int z1)
{
  int dx = abs (x1 - x0),
      dy = abs (y1 - y0),
      dz = abs (z1 - z0);

  if ((dx >= dy) && (dx >= dz))
    draw_3d_line_bresenham (x0, y0, z0, x1, y1, z1);
  else if ((dy >= dx) && (dy >= dz))
    draw_3d_line_bresenham (y0, x0, z0, y1, x1, z1);
  else
    draw_3d_line_bresenham (z0, x0, y0, z1, x1, y1);
}

float vol_draw_cube_fill_value (int x, int y, int z, int size)
{
  int center = ceil ((float) size / 2.f);

  int xm, ym, zm;
  if (x < center) xm = center - x;
  else            xm = x - (center - (size % 2 == 0 ? 1 : 2));
  if (y < center) ym = center - y;
  else            ym = y - (center - (size % 2 == 0 ? 1 : 2));
  if (z < center) zm = center - z;
  else            zm = z - (center - (size % 2 == 0 ? 1 : 2));

  float m = 0;
  if (m < xm)           m = xm;
  if (m < ym)           m = ym;
  if (z >= 0 && m < zm) m = zm;
  //d// printf ("X %d,%d,%d, %f, %d %d\n", x,y,z,m, center, size);

  return linerp (0.1, 0.9,
                 center <= 0 ? 0 : (m / (float) center));

}

void vol_draw_fill_pyramid (float x, float y, float z, float size)
{
  x    = ceil (x);
  y    = ceil (y);
  z    = ceil (z);
  size = ceil (size);

  int j, k, l;
  float pyr_size = size;
  for (k = 0; k < size; k++) // layer
    {
      for (j = 0; j < ceil (pyr_size); j++)
        for (l = 0; l < ceil (pyr_size); l++)
          {
            double val = vol_draw_cube_fill_value (j, l, -1, ceil (pyr_size));
            vol_draw_op ((float) j + x, (float) k + y, (float) l + z, val);
          }

      if (k % 2 == 1)
        pyr_size -= 2;
      x += 0.5;
      z += 0.5;
    }
}

void vol_draw_fill_box (float x, float y, float z, float size)
{
  int j, k, l;
  size = ceil (size);
  for (j = 0; j < size; j++)
    for (k = 0; k < size; k++)
      for (l = 0; l < size; l++)
        {
          int dx = x + j,
              dy = y + k,
              dz = z + l;
          double val = vol_draw_cube_fill_value (j, k, l, size);

          vol_draw_op (dx, dy, dz, val);
        }
}

void vol_draw_fill_sphere (float x, float y, float z, float size)
{
  float cntr = size / 2;
  vec3_init (center, x + cntr, y + cntr, z + cntr);

  float j, k, l;
  for (j = 0; j < size; j++)
    for (k = 0; k < size; k++)
      for (l = 0; l < size; l++)
        {
          vec3_init (cur, x + j, y + k, z + l);
          vec3_sub (cur, center);
          float vlen = vec3_len (cur);
          float diff = vlen - (cntr - (size / 10));

          if (diff < 0)
            {
              double sphere_val = (-diff / cntr);
              vol_draw_op (x + j, y + k, z + l, sphere_val);
            }
        }
}

void vol_draw_subdiv (int type, float x, float y, float z, float size, float shrink_fact, unsigned short lvl)
{
  float offs = size * 0.5f * shrink_fact;

  if (type == 1)
    vol_draw_fill_sphere (x + offs, y + offs, z + offs, size - 2 * offs);
  else if (type == 2)
    vol_draw_fill_pyramid (x + offs, y + offs, z + offs, size - 2 * offs);
  else
    vol_draw_fill_box (x + offs, y + offs, z + offs, size - 2 * offs);

  if (lvl > 1)
    {
      float cntr = size / 2;

      vol_draw_subdiv (type, x,        y, z,               cntr, shrink_fact, lvl - 1);
      vol_draw_subdiv (type, x,        y, z + cntr,        cntr, shrink_fact, lvl - 1);
      vol_draw_subdiv (type, x + cntr, y, z,               cntr, shrink_fact, lvl - 1);
      vol_draw_subdiv (type, x + cntr, y, z + cntr,        cntr, shrink_fact, lvl - 1);

      vol_draw_subdiv (type, x,        y + cntr, z,        cntr, shrink_fact, lvl - 1);
      vol_draw_subdiv (type, x,        y + cntr, z + cntr, cntr, shrink_fact, lvl - 1);
      vol_draw_subdiv (type, x + cntr, y + cntr, z,        cntr, shrink_fact, lvl - 1);
      vol_draw_subdiv (type, x + cntr, y + cntr, z + cntr, cntr, shrink_fact, lvl - 1);
    }
}

void vol_draw_self_sim_cubes (float x, float y, float z, float size, unsigned int corners, unsigned int seed, unsigned short lvl)
{
  if (lvl >= 1)
    {
      if (corners > 7)
        corners = 7;

      unsigned char corner_mask = 0x0;

      int i;
      unsigned int rnd = rnd_xor (seed);
      for (i = 0; i < corners; i++)
        {
          double val = (double) rnd / (double) 0xFFFFFFFF;
          int corner = floor ((val - 0.00000001) * 8.);
          while (corner_mask & (1 << corner))
            corner = (corner + 1) % 8;
          corner_mask |= 1 << corner;
          rnd = rnd_xor (rnd);
        }

      float cntr = size / 2;

      if (!(corner_mask & (1 << 0)))
         vol_draw_self_sim_cubes (x, y, z, cntr, corners, rnd = rnd_xor (rnd), lvl - 1);

      if (!(corner_mask & (1 << 1)))
        vol_draw_self_sim_cubes (x, y, z + cntr, cntr, corners, rnd = rnd_xor (rnd), lvl - 1);

      if (!(corner_mask & (1 << 2)))
        vol_draw_self_sim_cubes (x + cntr, y, z, cntr, corners, rnd = rnd_xor (rnd), lvl - 1);

      if (!(corner_mask & (1 << 3)))
        vol_draw_self_sim_cubes (x + cntr, y, z + cntr, cntr, corners, rnd = rnd_xor (rnd), lvl - 1);

      if (!(corner_mask & (1 << 4)))
        vol_draw_self_sim_cubes (x, y + cntr, z, cntr, corners, rnd = rnd_xor (rnd), lvl - 1);

      if (!(corner_mask & (1 << 5)))
        vol_draw_self_sim_cubes (x, y + cntr, z + cntr, cntr, corners, rnd = rnd_xor (rnd), lvl - 1);

      if (!(corner_mask & (1 << 6)))
        vol_draw_self_sim_cubes (x + cntr, y + cntr, z, cntr, corners, rnd = rnd_xor (rnd), lvl - 1);

      if (!(corner_mask & (1 << 7)))
        vol_draw_self_sim_cubes (x + cntr, y + cntr, z + cntr, cntr, corners, rnd = rnd_xor (rnd), lvl - 1);
    }
  else
    vol_draw_fill_box (x, y, z, size);
}

void vol_draw_self_sim_cubes_hash_seed (float x, float y, float z, float size, unsigned int corners, unsigned int seed, unsigned short lvl)
{
  seed = hash32int (seed); // make it a bit more random :)
  vol_draw_self_sim_cubes (x, y, z, size, corners, seed, lvl);
}

void vol_draw_sierpinski_pyramid (float x, float y, float z, float size, unsigned short lvl)
{
  if (lvl == 0)
    {
      vol_draw_fill_pyramid (x, y, z, size);
      return;
    }

  float half = size / 2;
  vol_draw_sierpinski_pyramid (x,        y, z,        half, lvl - 1);
  vol_draw_sierpinski_pyramid (x + half, y, z,        half, lvl - 1);
  vol_draw_sierpinski_pyramid (x,        y, z + half, half, lvl - 1);
  vol_draw_sierpinski_pyramid (x + half, y, z + half, half, lvl - 1);
  vol_draw_sierpinski_pyramid (x + (half / 2), y + half, z + (half / 2), half, lvl - 1);
}

void vol_draw_fill_simple_noise_octaves (unsigned int seed, unsigned int octaves, double factor, double persistence)
{
  double amp_correction = 0;

  void *noise = mk_3d_noise (DRAW_CTX.size, seed);

  int x, y, z;
  for (z = 0; z < DRAW_CTX.size; z++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (x = 0; x < DRAW_CTX.size; x++)
        DRAW_DST(x,y,z) = 0;

  int i;
  for (i = 0; i <= octaves; i++)
    {
      double scale = pow (factor, octaves - i);
      double amp   = pow (persistence , i);
      amp_correction += amp;

      for (z = 0; z < DRAW_CTX.size; z++)
        for (y = 0; y < DRAW_CTX.size; y++)
          for (x = 0; x < DRAW_CTX.size; x++)
            {
              unsigned int s = sample_3d_noise_at (noise, x, y, z, scale);
              double val = (double) s / (double) 0xFFFFFFFF;
              DRAW_DST(x,y,z) += val * amp;
            }
    }

  free_3d_noise (noise);

  for (z = 0; z < DRAW_CTX.size; z++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (x = 0; x < DRAW_CTX.size; x++)
        DRAW_DST(x,y,z) /= amp_correction;
}

// Utility function for vol_draw_mandel_box ().
double _vol_draw_mandel_box_equation (double *v, double s, double r, double f, double *c)
{
  //printf ("TEST %lf %lf %lf: %lf %lf %lf, %lf %lf %lf\n", v[0], v[1], v[2], s, r, f, c[0], c[1], c[2]);
  vec3_clone (fold, v);
  int i;
  for (i = 0; i < 3; i++)
    {
      if (fold[i] > 1)       fold[i] = (double) 2.0 - fold[i];
      else if (fold[i] < -1) fold[i] = (double) -2.0 - fold[i];
    }

  vec3_s_mul (fold, f);
  double m = vec3_len (fold);
  if (m < r)      { vec3_s_mul (fold, 4); }
  else if (m < 1) { vec3_s_div (fold, m * m); }
  vec3_assign (v, fold);
  vec3_s_mul (v, s);
  vec3_add (v, c);

  return vec3_len (v);
}

/* This function implements the mandel box fractal.
 * It's quite expensive and not used anywhere yet.
 */
void vol_draw_mandel_box (double xc, double yc, double zc, double xsc, double ysc, double zsc, double s, double r, double f, int it, double cfact)
{

  int x, y, z;
  for (z = 0; z < DRAW_CTX.size; z++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (x = 0; x < DRAW_CTX.size; x++)
        {
          vec3_init (c, x, y, z);
          vec3_s_div (c, DRAW_CTX.size);
          c[0] += xsc;
          c[1] += ysc;
          c[2] += zsc;
          vec3_s_mul (c, cfact);

          c[0] += -xsc * cfact;
          c[1] += -ysc * cfact;
          c[2] += -zsc * cfact;
          c[0] += xc;
          c[1] += yc;
          c[2] += zc;

          int i;
          int escape = 0;
          vec3_init (v, 0, 0, 0);
          for (i = 0; i < it; i++)
            {
              double d = _vol_draw_mandel_box_equation (v, s, r, f, c);
              if (d > 1024)
                {
                  escape = 1;
                  break;
                }
            }

          if (!escape)
            vol_draw_op (x, y, z, 0.5);
        }
}


// This function draws a menger sponge like structure to the volume.
void vol_draw_menger_sponge_box (float x, float y, float z, float size, unsigned short lvl)
{
  if (lvl == 0)
    {
      vol_draw_fill_box (x, y, z, size);
      return;
    }

   float j, k, l;
   float s3 = size / 3;
   for (j = 0; j < 3; j++)
     for (k = 0; k < 3; k++)
       for (l = 0; l < 3; l++)
         {
           int cnt_max = 0;
           if (j == 0 || j == 2)
             cnt_max++;
           if (k == 0 || k == 2)
             cnt_max++;
           if (l == 0 || l == 2)
             cnt_max++;

           if (cnt_max < 2)
             continue;

           vol_draw_menger_sponge_box (
             x + j * s3, y + k * s3, z + l * s3, s3, lvl - 1);
         }
}

// This algorithm draws some cantor dust like boxes recursively to the volume.
void vol_draw_cantor_dust_box (float x, float y, float z, float size, unsigned short lvl)
{
  if (lvl == 0)
    {
      vol_draw_fill_box (x, y, z, size);
      return;
    }

   float rad = (float) lvl;
   rad = rad < 1 ? 1 : rad;

   size /= 2;
   size -= rad;

   float offs = size + 2 * rad;

   vol_draw_cantor_dust_box (x,        y,        z,        size, lvl - 1);
   vol_draw_cantor_dust_box (x + offs, y,        z,        size, lvl - 1);
   vol_draw_cantor_dust_box (x       , y,        z + offs, size, lvl - 1);
   vol_draw_cantor_dust_box (x + offs, y,        z + offs, size, lvl - 1);

   vol_draw_cantor_dust_box (x,        y + offs, z,        size, lvl - 1);
   vol_draw_cantor_dust_box (x + offs, y + offs, z,        size, lvl - 1);
   vol_draw_cantor_dust_box (x       , y + offs, z + offs, size, lvl - 1);
   vol_draw_cantor_dust_box (x + offs, y + offs, z + offs, size, lvl - 1);
}

// Copy grey voxel values from the internal structures.
void vol_draw_copy (void *dst_arr)
{
  double *model = dst_arr;
  int x, y ,z;
  for (x = 0; x < DRAW_CTX.size; x++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (z = 0; z < DRAW_CTX.size; z++)
        model[x + y * DRAW_CTX.size + z * DRAW_CTX.size * DRAW_CTX.size]
           = DRAW_DST(x,y,z);
}

