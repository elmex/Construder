#include <stdio.h>
#include <arpa/inet.h>
#include "vectorlib.c"
#include <assert.h>

#define CHUNK_SIZE 12
#define CHUNK_ALEN (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)
#define POSSIBLE_OBJECTS 4096 // this is the max number of different object types!

#define myabs(x) ((x) < 0 ? -(x) : (x))
#define REL_POS2OFFS(x,y,z) (myabs (x) + myabs (y) * CHUNK_SIZE + myabs (z) * (CHUNK_SIZE * CHUNK_SIZE))

#include "world_data_struct.c"

typedef struct _b3d_obj_attr {
  unsigned short transparent : 1;
  unsigned short blocking    : 1;
} b3d_obj_attr;

typedef struct _b3d_cell {
   unsigned short type;
   unsigned char  light;
   unsigned char  meta;
   unsigned char  add;
   unsigned char  visible : 1;
   unsigned char  pad     : 7; // some padding, for 6 bytes
} b3d_cell;

typedef struct _b3d_chunk {
    int x, y, z;
    b3d_cell cells[CHUNK_ALEN];
} b3d_chunk;

typedef struct _b3d_world {
    b3d_axis_array *y;
} b3d_world;

static b3d_obj_attr OBJ_ATTR_MAP[POSSIBLE_OBJECTS];
static b3d_world WORLD;

void b3d_world_init ()
{
  int i;
  WORLD.y = b3d_axis_array_new ();
  memset (OBJ_ATTR_MAP, 0, sizeof (OBJ_ATTR_MAP));
}

b3d_obj_attr *b3d_world_get_attr (unsigned int type)
{
  return &(OBJ_ATTR_MAP[type]);
}

void b3d_world_set_object_type (
        unsigned int type, unsigned int transparent, unsigned int blocking)
{
  b3d_obj_attr *oa = b3d_world_get_attr (type);
  oa->transparent = transparent;
  oa->blocking    = blocking;
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
  unsigned int offs = REL_POS2OFFS (xi, yi, zi);
  return &(chnk->cells[offs]);
}

void b3d_world_chunk_calc_visibility (b3d_chunk *chnk)
{
  unsigned int x, y, z;
  for (z = 0; z < CHUNK_SIZE; z++)
    for (y = 0; y < CHUNK_SIZE; y++)
      for (x = 0; x < CHUNK_SIZE; x++)
        {
          unsigned int offs = REL_POS2OFFS (x, y, z);
          chnk->cells[offs].visible = 0;
        }

  for (z = 0; z < CHUNK_SIZE; z++)
    for (y = 0; y < CHUNK_SIZE; y++)
      for (x = 0; x < CHUNK_SIZE; x++)
        {
          unsigned int offs = REL_POS2OFFS (x, y, z);
          b3d_cell *cell = &(chnk->cells[offs]);
          b3d_obj_attr *oa = b3d_world_get_attr (cell->type);
          cell->visible = 1;
          if (oa->transparent)
            {
              cell->visible = 1;

              unsigned int i,d,k;
              for (i = -1; i <= 1; i++)
                for (d = -1; d <= 1; d++)
                  for (k = -1; k <= 1; k++)
                    chnk->cells[REL_POS2OFFS (x + i, y + d, z + k)].visible = 1;
            }
        }
}

void b3d_world_set_chunk_from_data (b3d_chunk *chnk, unsigned char *data, unsigned int len)
{
  unsigned int x, y, z;
  for (z = 0; z < CHUNK_SIZE; z++)
    for (y = 0; y < CHUNK_SIZE; y++)
      for (x = 0; x < CHUNK_SIZE; x++)
        {
          unsigned int offs = REL_POS2OFFS (x, y, z);
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
          unsigned int offs = REL_POS2OFFS (x, y, z);
          b3d_get_data_from_cell (&(chnk->cells[offs]), data + (offs * 4));
        }
}

b3d_chunk *b3d_world_chunk (int x, int y, int z, int alloc)
{
  b3d_axis_array *xn = (b3d_axis_array *) b3d_axis_get (WORLD.y, y);
  if (!xn)
    {
      if (alloc)
        {
          xn = b3d_axis_array_new ();
          b3d_axis_add (WORLD.y, y, xn);
        }
      else
        return 0;
    }

  b3d_axis_array *zn = (b3d_axis_array *) b3d_axis_get (xn, x);
  if (!zn)
    {
      if (alloc)
        {
          zn = b3d_axis_array_new ();
          b3d_axis_add (xn, x, zn);
        }
      else
        return 0;
    }

  b3d_chunk *c = (b3d_chunk *) b3d_axis_get (zn, z);
  if (alloc && !c)
    {
      c = malloc (sizeof (b3d_chunk));
      memset (c, 0, sizeof (b3d_chunk));
      c->x = x;
      c->y = y;
      c->z = z;
      b3d_axis_add (zn, z, c);
    }

  return c;
}

b3d_chunk *b3d_world_chunk_at (double x, double y, double z, int alloc)
{
  vec3_init (pos, x, y, z);
  vec3_s_div (pos, CHUNK_SIZE);
  vec3_floor (pos);
  return b3d_world_chunk (pos[0], pos[1], pos[2], alloc);
}

void b3d_world_purge_chunk (int x, int y, int z)
{
  b3d_axis_array *xn = (b3d_axis_array *) b3d_axis_get (WORLD.y, y);
  if (!xn)
    return;

  b3d_axis_array *zn = (b3d_axis_array *) b3d_axis_get (xn, x);
  if (!zn)
    return;

  b3d_chunk *c = (b3d_chunk *) b3d_axis_remove (zn, z);
  if (c)
    free (c);
}


void b3d_world_dump ()
{
  unsigned int x, y, z;
  printf ("WORLD:\n");
  for (y = 0; y < WORLD.y->len; y++)
    {
      b3d_axis_node *any = &(WORLD.y->nodes[y]);
      b3d_axis_array *xa = (b3d_axis_array *) any->ptr;

      for (x = 0; x < xa->len; x++)
        {
          b3d_axis_node *anx = &(xa->nodes[x]);
          b3d_axis_array *za = (b3d_axis_array *) anx->ptr;
          if (za)
            {
              for (z = 0; z < za->len; z++)
                {
                  b3d_axis_node *anz = &(za->nodes[z]);
                  b3d_chunk *cnk = (b3d_chunk *) anz->ptr;
                  printf ("[%d %d %d] %p(%d,%d,%d)\n", anx->coord, any->coord, anz->coord, anz->ptr, cnk->x, cnk->y, cnk->z);
                }
            }
        }
    }
}
