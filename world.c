#include <stdio.h>
#include <arpa/inet.h>
#include "vectorlib.c"

#define CHUNK_SIZE 12
#define CHUNK_ALEN (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)

#define myabs(x) ((x) < 0 ? -(x) : (x))
#define CHUNK2OFFS(x,y,z) (myabs (x) + myabs (y) * CHUNK_SIZE + myabs (z) * (CHUNK_SIZE * CHUNK_SIZE))

//   my ($blk, $meta, $add) = unpack "nCC", $dat;
//   my ($type, $light) = (($blk & 0xFFF0) >> 4, ($blk & 0x000F));
//   [$type, $light, $meta, $add]

typedef struct _b3d_cell {
   unsigned short type;
   unsigned char  light;
   unsigned char  meta;
   unsigned char  add;
   unsigned char  pad; // some padding, for 6 bytes
} b3d_cell;

typedef struct _b3d_chunk {
    b3d_cell cells[CHUNK_ALEN];
} b3d_chunk;

typedef struct _b3d_chunk_collection {
    unsigned int alloc;
    b3d_chunk **chunks;
} b3d_chunk_collection;

typedef struct _b3d_world {
  b3d_chunk_collection  quadrants[8];
} b3d_world;

static b3d_world WORLD;

void b3d_chunk_collection_init (b3d_chunk_collection *cc)
{
  cc->alloc  = 16;
  cc->chunks = malloc (sizeof (b3d_chunk *) * cc->alloc);
  memset (cc->chunks, 0, sizeof (b3d_chunk *) * cc->alloc);
}

void b3d_chunk_collection_grow (b3d_chunk_collection *cc, unsigned int min_size)
{
  unsigned int old_alloc = cc->alloc;
  while (cc->alloc < min_size)
    {
      printf ("alloc %d\n", cc->alloc);
      cc->alloc *= 2;
    }

  b3d_chunk **chunks = malloc (sizeof (b3d_chunk *) * cc->alloc);
  memset (chunks, 0, sizeof (b3d_chunk *) * cc->alloc);
  memcpy (chunks, cc->chunks, sizeof (b3d_chunk *) * old_alloc);
  free (cc->chunks);
  cc->chunks = chunks;
}

void b3d_world_init ()
{
  int i;
  for (i = 0; i < 8; i++)
    b3d_chunk_collection_init (&(WORLD.quadrants[i]));
}

void b3d_set_cell_from_data (b3d_cell *c, unsigned char *ptr)
{
 //d//printf ("CELL dATA %p: %02x %02x %02x %02x\n", c, *ptr, *(ptr + 1), *(ptr + 2), *(ptr + 3));
  unsigned short *sptr = (short *) ptr;
  unsigned short blk = ntohs (*sptr);
  c->type  = ((blk & 0xFFF0) >> 4);
  c->light = blk & 0x000F;

  sptr++;
  ptr = (unsigned char *) sptr;
  c->meta = *ptr;
  ptr++;
  c->add  = *ptr;
}

void b3d_get_data_from_cell (b3d_cell *c, unsigned char *ptr)
{
  unsigned char *optr = ptr;
  unsigned short *sptr = (short *) ptr;
  (*sptr) = htons ((c->type << 4) & 0xFFF0 | c->light & 0x000F);

  sptr++;
  ptr = (unsigned char *) sptr;
  *ptr = c->meta;
  ptr++;
  *ptr = c->add;
 //d//printf ("CELL GET DATA %p: %02x %02x %02x %02x\n", c, *optr, *(optr + 1), *(optr + 2), *(optr + 3));
}

b3d_chunk *b3d_world_chunk (int x, int y, int z)
{
  unsigned int q =
      (x < 0 ? 0x1 : 0)
    | (y < 0 ? 0x2 : 0)
    | (z < 0 ? 0x4 : 0);
  b3d_chunk_collection *cc = &(WORLD.quadrants[q]);
  unsigned int offs = CHUNK2OFFS(x, y, z);

  if (offs >= cc->alloc)
    b3d_chunk_collection_grow (cc, offs);

  if (cc->chunks[offs])
    {
      return cc->chunks[offs];
    }
  else
    {
      cc->chunks[offs] = malloc (sizeof (b3d_chunk));
      memset (cc->chunks[offs], 0, sizeof (b3d_chunk));
      return cc->chunks[offs];
    }
}

void b3d_world_purge_chunk (int x, int y, int z)
{
  unsigned int q =
      (x < 0 ? 0x1 : 0)
    | (y < 0 ? 0x2 : 0)
    | (z < 0 ? 0x4 : 0);
  b3d_chunk_collection *cc = &(WORLD.quadrants[q]);
  unsigned int offs = CHUNK2OFFS(x, y, z);

  if (offs >= cc->alloc)
    return;
  if (!cc->chunks[offs])
    return;
  free (cc->chunks[offs]);
  cc->chunks[offs] = 0;
}

b3d_chunk *b3d_world_chunk_at (double x, double y, double z)
{
  vec3_init (pos, x, y, z);
  vec3_s_div (pos, CHUNK_SIZE);
  vec3_floor (pos);
  return b3d_world_chunk (pos[0], pos[1], pos[2]);
}

b3d_cell *b3d_chunk_cell_at_abs (b3d_chunk *chnk, double x, double y, double z)
{
  vec3_init (pos, x, y, z);
  vec3_s_div (pos, CHUNK_SIZE);
  vec3_floor (pos);
  x -= pos[0] * CHUNK_SIZE;
  y -= pos[1] * CHUNK_SIZE;
  z -= pos[2] * CHUNK_SIZE;
  x = floor (x);
  y = floor (y);
  z = floor (z);
  int xi = x, yi = y, zi = z;
  unsigned int offs = CHUNK2OFFS (xi, yi, zi);
  return &(chnk->cells[offs]);
}

void b3d_world_set_chunk_from_data (b3d_chunk *chnk, unsigned char *data, unsigned int len)
{
  unsigned int x, y, z;
  for (z = 0; z < CHUNK_SIZE; z++)
    for (y = 0; y < CHUNK_SIZE; y++)
      for (x = 0; x < CHUNK_SIZE; x++)
        {
          unsigned int offs = CHUNK2OFFS (x, y, z);
          if (len > (offs * 4) + 3)
            b3d_set_cell_from_data (&(chnk->cells[offs]), data + (offs * 4));
          else
            {
              //d//printf ("BAD OFFSET: %d vs %d\n", offs * 4, len);
              exit (1);
            }
        }
}

void b3d_world_get_chunk_data (b3d_chunk *chnk, unsigned char *data)
{
  unsigned int x, y, z;
  for (z = 0; z < CHUNK_SIZE; z++)
    for (y = 0; y < CHUNK_SIZE; y++)
      for (x = 0; x < CHUNK_SIZE; x++)
        {
          unsigned int offs = CHUNK2OFFS (x, y, z);
          b3d_get_data_from_cell (&(chnk->cells[offs]), data + (offs * 4));
        }
}
