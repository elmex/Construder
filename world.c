#include <stdio.h>
#include <arpa/inet.h>

#define CHUNK_SIZE 12
#define CHUNK_ALEN (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)


   my ($blk, $meta, $add) = unpack "nCC", $dat;
   my ($type, $light) = (($blk & 0xFFF0) >> 4, ($blk & 0x000F));
   [$type, $light, $meta, $add]

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
    unsigned int len;
    b3d_chunk *chunks;
} b3d_chunk_collection;

typedef struct _b3d_world {
  b3d_chunk_collection  quadrants[8];
} b3d_world;

static b3d_world WORLD;

void b3d_chunk_collection_init (b3d_chunk_collection *cc)
{
  cc->alloc  = 16;
  cc->len    = 0;
  cc->chunks = malloc (sizeof (b3d_chunk) * cc->alloc);
  memset (cc->chunks, 0, sizeof (b3d_chunk));
}

void b3d_chunk_collection_grow (b3d_chunk_collection *cc, unsigned int min_size)
{
  unsigned int old_alloc = cc->alloc;
  while (cc->alloc < min_size)
    cc->alloc *= 2;

  b3d_chunk *chunks = malloc (sizeof (b3d_chunk) * cc->alloc);
  memcpy (chunks, cc->chunks, sizeof (b3d_chunk) * old_alloc);
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
  unsigned short *sptr = (short *) ptr;
  unsigned short blk = ntohs (*sptr);
  c->type  = (blk & 0xFFF0 >> 4);
  c->light = blk & 0x000F;

  sptr++;
  ptr = (unsigned char *) sptr;
  c->meta = *ptr;
  ptr++;
  c->add  = *ptr;
}

void b3d_set_cell_to_data (b3d_cell *c, unsigned char *ptr)
{
  unsigned short *sptr = (short *) ptr;
  (*sptr) = hston ((c->type << 4) | c->light & 0x000F);
  sptr++;
  ptr = (unsigned char *) sptr;

  *ptr = c->meta;
  ptr++;
  *ptr = c->add;
}

b3d_chunk *b3d_world_chunk (int x, int y, int z)
{
  unsigned int q =
      (x < 0 ? 0x1 : 0)
    | (y < 0 ? 0x2 : 0)
    | (z < 0 ? 0x4 : 0);
  b3d_chunk_collection *cc = &(WORLD.quadrants[q]);
  unsigned int offs = x + y * CHUNK_SIZE + z * (CHUNK_SIZE * CHUNK_SIZE);
  if (offs >= cc->len)
    b3d_chunk_collection_grow (cc, offs);
  return &(cc->chunks[offs])
}

b3d_chunk *b3d_world_chunk_at (double x, double y, double z)
{
  vec3_init (pos, x, y, z);
  vec3_s_div (pos, CHUNK_SIZE);
  vec3_floor (pos);
  return b3d_world_chunk (pos[0], pos[1], pos[2]);
}

void b3d_world_set_chunk_from_data (b3d_chunk *chnk, unsigned char *data, unsigned int len)
{
  unsigned int x, y, z;
  for (z = 0; z < CHUNK_SIZE; z++)
    for (y = 0; y < CHUNK_SIZE; y++)
      for (x = 0; x < CHUNK_SIZE; x++)
        {
          unsigned int offs = x + y * CHUNK_SIZE + z * CHUNK_SIZE * CHUNK_SIZE;
          if (len <= offs + 4)
            b3d_set_cell_from_data (chnk->[offs], data + (offs * 4));
        }
}

void b3d_world_get_chunk_data (b3d_chunk *chunk, unsigned char *data)
{
  unsigned int x, y, z;
  for (z = 0; z < CHUNK_SIZE; z++)
    for (y = 0; y < CHUNK_SIZE; y++)
      for (x = 0; x < CHUNK_SIZE; x++)
        {
          unsigned int offs = x + y * CHUNK_SIZE + z * CHUNK_SIZE * CHUNK_SIZE;
          b3d_set_cell_to_data (chnk->[offs], data + (offs * 4));
        }
}
