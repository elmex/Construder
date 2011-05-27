#include <math.h>
#include "vectorlib.c"
#include "noise_3d.c"

typedef struct _vol_draw_ctx {
  unsigned int size;
  double      *buffers[4];
  double      *src;
  double      *dst;

  unsigned int draw_op;
  double  dst_range[2];
  double  src_range[2];
  double  src_blend;

#define VOL_DRAW_ADD 1
#define VOL_DRAW_SUB 2
#define VOL_DRAW_MUL 3
#define VOL_DRAW_SET 4

} vol_draw_ctx;

#define DRAW_DST(x,y,z) DRAW_CTX.dst[((unsigned int) (x)) + ((unsigned int) (y)) * DRAW_CTX.size + ((unsigned int) (z)) * (DRAW_CTX.size * DRAW_CTX.size)]
#define DRAW_SRC(x,y,z) DRAW_CTX.src[((unsigned int) (x)) + ((unsigned int) (y)) * DRAW_CTX.size + ((unsigned int) (z)) * (DRAW_CTX.size * DRAW_CTX.size)]

// two buffers:
//    source
//    dest
//
// Draw Styles:
//   - cantor dust
//   - menger sponge
//   - sphere-fractal-like: 2 styles: value range fill, empty
//   - random spheres: also 2 styles
//
// Fill Styles:
//   - noise octaves with parameters
//   - constant fill from [0,1]
//   - draw board source (operation: swap dest/source buffer)
//
// Draw Ops:
//   - add
//   - sub
//   - mul
//   - set

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
  if (DRAW_CTX.src)
    {
      for (i = 0; i < 4; i++)
        free (DRAW_CTX.buffers[i]);
    }

  for (i = 0; i < 4; i++)
    {
      DRAW_CTX.buffers[i] = malloc (sizeof (double) * size * size * size);
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

void vol_draw_src_range (double a, double b)
{
  int x, y, z;
  for (z = 0; z < DRAW_CTX.size; z++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (x = 0; x < DRAW_CTX.size; x++)
        {
          if (DRAW_SRC(x, y, z) >= a && DRAW_SRC(x, y, z) < b)
            vol_draw_op (x, y, z, DRAW_SRC (x, y, z));
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

void vol_draw_sphere_subdiv (float x, float y, float z, float size, unsigned short lvl)
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

  if (lvl > 1)
    {
      vol_draw_sphere_subdiv (x,        y, z,               cntr, lvl - 1);
      vol_draw_sphere_subdiv (x,        y, z + cntr,        cntr, lvl - 1);
      vol_draw_sphere_subdiv (x + cntr, y, z,               cntr, lvl - 1);
      vol_draw_sphere_subdiv (x + cntr, y, z + cntr,        cntr, lvl - 1);

      vol_draw_sphere_subdiv (x,        y + cntr, z,        cntr, lvl - 1);
      vol_draw_sphere_subdiv (x,        y + cntr, z + cntr, cntr, lvl - 1);
      vol_draw_sphere_subdiv (x + cntr, y + cntr, z,        cntr, lvl - 1);
      vol_draw_sphere_subdiv (x + cntr, y + cntr, z + cntr, cntr, lvl - 1);
    }
}

void vol_draw_fill_simple_noise_octaves (unsigned int seed, unsigned int octaves, double factor, double persistence)
{
  double amp_correction = 0;

  if (seed == 0) seed = 1;
  printf ("SEED NOISE %d\n", seed);

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
              unsigned long s = sample_3d_noise_at (noise, x, y, z, scale);
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

void vol_draw_fill_box (float x, float y, float z, float size)
{
  int j, k, l;
  for (j = 0; j < size; j++)
    for (k = 0; k < size; k++)
      for (l = 0; l < size; l++)
        {
          int lm = abs (l - (size / 2));
          int km = abs (k - (size / 2));
          int jm = abs (j - (size / 2));

          int m = 0;
          if (m < lm) m = lm;
          if (m < km) m = km;
          if (m < jm) m = jm;
          double val = linerp (0.1, 0.9, (m / (size / 2)));

          int dx = x + j,
              dy = y + k,
              dz = z + l;

          if (dx >= DRAW_CTX.size
              || dy >= DRAW_CTX.size
              || dz >= DRAW_CTX.size)
            continue;

          vol_draw_op (dx, dy, dz, val);
        }
}

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

