#include <math.h>
#include "noise_3d.c"

typedef struct _vol_draw_ctx {
  unsigned int size;
  double      *src;
  double      *dst;

  unsigned int draw_op;

#define VOL_DRAW_ADD 1
#define VOL_DRAW_SUB 2
#define VOL_DRAW_MUL 3
#define VOL_DRAW_SET 4

} vol_draw_ctx;

#define DRAW_DST(x,y,z) DRAW_CTX.dst[(x) + (y) * DRAW_CTX.size + (z) * (DRAW_CTX.size * DRAW_CTX.size)]
#define DRAW_SRC(x,y,z) DRAW_CTX.src[(x) + (y) * DRAW_CTX.size + (z) * (DRAW_CTX.size * DRAW_CTX.size)]

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
  DRAW_CTX.dst  = 0;
  DRAW_CTX.size = 0;
  DRAW_CTX.draw_op = 0;
}

void vol_draw_alloc (unsigned int size)
{
  if (DRAW_CTX.src)
    {
      free (DRAW_CTX.src);
      free (DRAW_CTX.dst);
    }

  DRAW_CTX.src = malloc (sizeof (double) * size * size * size);
  DRAW_CTX.dst = malloc (sizeof (double) * size * size * size);
  memset (DRAW_CTX.src, 0, sizeof (double) * size * size * size);
  memset (DRAW_CTX.dst, 0, sizeof (double) * size * size * size);
  DRAW_CTX.size = size;
}

void vol_draw_set_op (unsigned int op)
{
  DRAW_CTX.draw_op = op;
}

void vol_draw_swap ()
{
  double *s = DRAW_CTX.src;
  DRAW_CTX.src = DRAW_CTX.dst;
  DRAW_CTX.dst = s;
}

void vol_draw_op (unsigned int x, unsigned int y, unsigned int z, double val)
{
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

void vol_fill (double val)
{
  int x, y, z;
  for (z = 0; z < DRAW_CTX.size; z++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (x = 0; x < DRAW_CTX.size; x++)
        DRAW_DST(x,y,z) = val;
}

void vol_draw_self ()
{
  int x, y, z;
  for (z = 0; z < DRAW_CTX.size; z++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (x = 0; x < DRAW_CTX.size; x++)
        vol_draw_op (x, y, z, DRAW_SRC (x, y, z));
}

void vol_fill_simple_noise_octaves (unsigned int seed, unsigned int octaves, double factor, double persistence)
{
  double amp_correction = 0;

  if (seed == 0) seed = 1;


  void *noise = mk_3d_noise (DRAW_CTX.size, seed);

  int i;
  for (i = 0; i <= octaves; i++)
    {
      double scale = pow (factor, octaves - i);
      double amp   = pow (persistence , i);
      amp_correction += amp;

      int x, y, z;
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

  int x, y, z;
  for (z = 0; z < DRAW_CTX.size; z++)
    for (y = 0; y < DRAW_CTX.size; y++)
      for (x = 0; x < DRAW_CTX.size; x++)
        DRAW_DST(x,y,z) /= amp_correction;
}

void vol_draw_model_menger_sponge_box (float x, float y, float z, float size, int max, int lvl)
{
  if (lvl == 0)
    {
      int j, k, l;
      for (j = 0; j < size; j++)
        for (k = 0; k < size; k++)
          for (l = 0; l < size; l++)
            vol_draw_op (x + j, y + k, z + l, DRAW_SRC((unsigned int) x + j, (unsigned int) y + k, (unsigned int) z + l));
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

           vol_draw_model_menger_sponge_box (
             x + j * s3, y + k * s3, z + l * s3, s3, max, lvl - 1);
         }
}
//
//
//void draw_model_cantor_dust_box (float x, float y, float z, float size, int max, int lvl)
//{
//  if (lvl == 0)
//    {
//        int j, k, l;
//     for (j = 0; j < size; j++)
//       for (k = 0; k < size; k++)
//         for (l = 0; l < size; l++)
//           {
//            int xi = x + j, yi = y + k, zi = z + l;
//             if (xi >= max || yi >= max || zi >= max)
//               return;
//            model[OFFS(xi, yi, zi)] = 1;
//           }
//      return;
//    }
//
//   float rad = (float) lvl / 1.3;
//   rad = rad < 1 ? 1 : rad;
//
//   size /= 2;
//   size -= rad;
//
//   float offs = size + 2 * rad;
//
//   draw_model_cantor_dust_box (x,        y,        z,        size, max, lvl - 1);
//   draw_model_cantor_dust_box (x + offs, y,        z,        size, max, lvl - 1);
//   draw_model_cantor_dust_box (x       , y,        z + offs, size, max, lvl - 1);
//   draw_model_cantor_dust_box (x + offs, y,        z + offs, size, max, lvl - 1);
//
//   draw_model_cantor_dust_box (x,        y + offs, z,        size, max, lvl - 1);
//   draw_model_cantor_dust_box (x + offs, y + offs, z,        size, max, lvl - 1);
//   draw_model_cantor_dust_box (x       , y + offs, z + offs, size, max, lvl - 1);
//   draw_model_cantor_dust_box (x + offs, y + offs, z + offs, size, max, lvl - 1);
//}
//
//
