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
/* This file implements some noise/random functions used by volume_draw.c
 * and other parts of the code.
 */
#define INTSCALE  (128ul)
#define INTSCALE3 (INTSCALE * INTSCALE * INTSCALE)
#include <stdint.h>

// xorshift pseudo random number generator.
unsigned int rnd_xor (unsigned int x)
{
   x ^= (x << 6);
   x ^= (x >> 3);
   x ^= (x << 17);
   return x;
}

// 32bit integer hash function.
unsigned int hash32int (unsigned int i)
{
  i = (i << 15) - i - 1;
  i = i ^ (i >> 12);
  i = i + (i << 2);
  i = i ^ (i >> 4);
  i = i * 2057;         // key = (key + (key << 3)) + (key << 11);
  i = i ^ (i >> 16);
  return i;
}

// Function to map 3 coordinates onto a single integer value.
unsigned int map_coord2int (unsigned int x, unsigned int y, unsigned int z)
{
  unsigned int out = 0;
  unsigned int i = 0;
  while (x > 0 || y > 0 || z > 0)
    {
      out += (x & 0x1) ? (0x1 << i) : 0;
      i++;
      out += (y & 0x1) ? (0x1 << i) : 0;
      i++;
      out += (z & 0x1) ? (0x1 << i) : 0;
      i++;
      x >>= 1;
      y >>= 1;
      z >>= 1;
    }

  return hash32int (out); // hashed so we can use this as initializer to a rng.
}

#define NOISE_ARR_OFFS(slen,x,y,z) (1 + (x) + (y) * slen + (z) * (slen * slen))

unsigned int linerp_int (unsigned int a, unsigned int b, unsigned int x)
{
   uint64_t i =
        ((uint64_t) a * (INTSCALE - x)) + ((uint64_t) b * x);
   i /= INTSCALE;
   return i;
}

unsigned int smoothstep_int (unsigned int a, unsigned int b, unsigned int x)
{
   uint64_t xs = x;
   xs = xs * xs * ((3 * INTSCALE) - 2 * xs);
   uint64_t i =
          ((uint64_t) a * (INTSCALE3 - xs))
        + ((uint64_t) b * xs);
   i /= INTSCALE3;
   return i;
}

// Create volume with value noise.
void *mk_3d_noise (unsigned int slen, unsigned int seed)
{
   int x, y, z;

   seed = hash32int (seed);

   slen++; // sample one more at the edge

   unsigned int *noise_arr =
      safemalloc (sizeof (unsigned int) * (slen * slen * slen + 1));

   noise_arr[0] = slen;

   for (x = 0; x < slen; x++)
     for (y = 0; y < slen; y++)
       for (z = 0; z < slen; z++)
         seed = noise_arr[NOISE_ARR_OFFS(slen,x,y,z)] = rnd_xor (seed);

   return noise_arr;
}

// Sample noise from a noise volume using interpolation.
unsigned int sample_3d_noise_at (void *noise, unsigned int x, unsigned int y, unsigned int z, unsigned int scale)
{
   unsigned int *noise_3d = noise;

   if (scale <= 0)
     return 0;

   // reduces the sampling scale, higher "scale" means less
   // points from noise are looked at and more interpolation

   unsigned int x_rest = (INTSCALE * (x % scale)) / scale;
   x /= scale;
   unsigned int y_rest = (INTSCALE * (y % scale)) / scale;
   y /= scale;
   unsigned int z_rest = (INTSCALE * (z % scale)) / scale;
   z /= scale;

   //d// printf ("red %d %d %d, rest %ud %ud %ud %ud\n", x, y, z, scale, x_rest, y_rest, z_rest);
   unsigned int slen = noise_3d[0];

   if ((z + 1) >= slen
       || (y + 1) >= slen
       || (x + 1) >= slen)
     return 0;

   unsigned int samples[8];
   samples[0] = noise_3d[NOISE_ARR_OFFS(slen,x    , y,     z)];
   samples[1] = noise_3d[NOISE_ARR_OFFS(slen,x + 1, y,     z)];

   samples[2] = noise_3d[NOISE_ARR_OFFS(slen,x    , y + 1, z)];
   samples[3] = noise_3d[NOISE_ARR_OFFS(slen,x + 1, y + 1, z)];

   samples[4] = noise_3d[NOISE_ARR_OFFS(slen,x    , y,     z + 1)];
   samples[5] = noise_3d[NOISE_ARR_OFFS(slen,x + 1, y,     z + 1)];

   samples[6] = noise_3d[NOISE_ARR_OFFS(slen,x    , y + 1, z + 1)];
   samples[7] = noise_3d[NOISE_ARR_OFFS(slen,x + 1, y + 1, z + 1)];

   samples[0] = smoothstep_int (samples[0], samples[1], x_rest);
   samples[1] = smoothstep_int (samples[2], samples[3], x_rest);
   samples[2] = smoothstep_int (samples[4], samples[5], x_rest);
   samples[3] = smoothstep_int (samples[6], samples[7], x_rest);

   samples[0] = smoothstep_int (samples[0], samples[1], y_rest);
   samples[1] = smoothstep_int (samples[2], samples[3], y_rest);

   return smoothstep_int (samples[0], samples[1], z_rest);
}

void free_3d_noise (void *noise)
{
  safefree (noise);
}


