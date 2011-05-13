#include <stdio.h>
#include <arpa/inet.h>
#include "vectorlib.c"
#include <assert.h>

#define CHUNK_SIZE 12
#define CHUNK_ALEN (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)
#define POSSIBLE_OBJECTS 4096 // this is the max number of different object types!
#define MAX_MODEL_DIM   4
#define MAX_MODEL_SIZE  (MAX_MODEL_DIM * MAX_MODEL_DIM * MAX_MODEL_DIM)

#define myabs(x) ((x) < 0 ? -(x) : (x))
#define REL_POS2OFFS(x,y,z) (myabs (x) + myabs (y) * CHUNK_SIZE + myabs (z) * (CHUNK_SIZE * CHUNK_SIZE))

#include "world_data_struct.c"

typedef struct _b3d_obj_attr {
  double uv[4];
  unsigned short transparent : 1;
  unsigned short blocking    : 1;
  unsigned short model       : 1;
  unsigned int   model_dim   : 3;
  unsigned int   model_blocks[MAX_MODEL_SIZE];
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
    SV *chunk_change_cb;
} b3d_world;

static b3d_obj_attr OBJ_ATTR_MAP[POSSIBLE_OBJECTS];
static b3d_world WORLD;
static b3d_cell neighbour_cell;

void b3d_world_init ()
{
  int i;
  WORLD.y = b3d_axis_array_new ();
  memset (OBJ_ATTR_MAP, 0, sizeof (OBJ_ATTR_MAP));
  neighbour_cell.type    = 0;
  neighbour_cell.light   = 15;
  neighbour_cell.add     = 0;
  neighbour_cell.meta    = 0;
  neighbour_cell.visible = 1;
}

//void b3d_world_emit_chunk_change_obj (int x, int y, int z, int act, unsigned int id)
//{
//  if (WORLD.chunk_change_cb)
//    {
//      dSP;
//      ENTER;
//      SAVETMPS;
//      PUSHMARK(SP);
//      XPUSHs(sv_2mortal(newSViv (x)));
//      XPUSHs(sv_2mortal(newSViv (y)));
//      XPUSHs(sv_2mortal(newSViv (z)));
//      XPUSHs(sv_2mortal(newSViv (act)));
//      XPUSHs(sv_2mortal(newSViv (id)));
//      PUTBACK;
//      call_sv (WORLD.chunk_change_cb, G_DISCARD | G_VOID);
//      SPAGAIN;
//      FREETMPS;
//      LEAVE;
//    }
//}

void b3d_world_emit_chunk_change (int x, int y, int z)
{
  if (WORLD.chunk_change_cb)
    {
      dSP;
      ENTER;
      SAVETMPS;
      PUSHMARK(SP);
      XPUSHs(sv_2mortal(newSViv (x)));
      XPUSHs(sv_2mortal(newSViv (y)));
      XPUSHs(sv_2mortal(newSViv (z)));
      PUTBACK;
      call_sv (WORLD.chunk_change_cb, G_DISCARD | G_VOID);
      SPAGAIN;
      FREETMPS;
      LEAVE;
    }
}

b3d_obj_attr *b3d_world_get_attr (unsigned int type)
{
  return &(OBJ_ATTR_MAP[type]);
}

void b3d_world_set_object_type (
        unsigned int type, unsigned int transparent, unsigned int blocking,
        double uv0, double uv1, double uv2, double uv3)
{
  b3d_obj_attr *oa = b3d_world_get_attr (type);
  oa->transparent = transparent;
  oa->blocking    = blocking;
  oa->uv[0]       = uv0;
  oa->uv[1]       = uv1;
  oa->uv[2]       = uv2;
  oa->uv[3]       = uv3;
}

void b3d_world_set_object_model (unsigned int type, unsigned int dim, AV *blocks)
{
  b3d_obj_attr *oa = b3d_world_get_attr (type);
  oa->model        = 1;
  oa->model_dim    = dim;

  int midx = av_len (blocks);
  if (midx < 0)
    return;

  int i;
  for (i = 0; i <= midx; i++)
    {
      SV **block = av_fetch (blocks, i, 0);
      if (!block)
        continue;
      oa->model_blocks[i] = SvIV (*block);
    }
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

b3d_cell *b3d_chunk_cell_at_rel (b3d_chunk *chnk, unsigned int x, unsigned int y, unsigned int z)
{
  unsigned int offs = REL_POS2OFFS (x, y, z);
  return &(chnk->cells[offs]);
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

int b3d_world_cell_transparent (b3d_cell *c)
{
  b3d_obj_attr *oa = b3d_world_get_attr (c->type);
  return oa->transparent;
}


b3d_cell *
b3d_world_chunk_neighbour_cell (b3d_chunk *c, int x, int y, int z, b3d_chunk *neigh_chunk)
{
  if (   x < 0 || y < 0 || z < 0
      || x >= CHUNK_SIZE || y >= CHUNK_SIZE || z >= CHUNK_SIZE)
    {
      if (neigh_chunk)
        {
          if (x < 0) x += CHUNK_SIZE;
          if (y < 0) y += CHUNK_SIZE;
          if (z < 0) z += CHUNK_SIZE;
          if (x >= CHUNK_SIZE) x -= CHUNK_SIZE;
          if (y >= CHUNK_SIZE) y -= CHUNK_SIZE;
          if (z >= CHUNK_SIZE) z -= CHUNK_SIZE;
          c = neigh_chunk;
        }
      else
        return &neighbour_cell;
    }

  unsigned int offs = REL_POS2OFFS(x, y, z);

  return &(c->cells[offs]);
}

#define LOAD_NEIGHBOUR_CHUNKS(x,y,z) \
  b3d_chunk *top_chunk = b3d_world_chunk (x, y + 1, z, 0); \
  b3d_chunk *bot_chunk = b3d_world_chunk (x, y - 1, z, 0); \
  b3d_chunk *left_chunk = b3d_world_chunk (x - 1, y, z, 0); \
  b3d_chunk *right_chunk = b3d_world_chunk (x + 1, y, z, 0); \
  b3d_chunk *front_chunk = b3d_world_chunk (x, y, z - 1, 0); \
  b3d_chunk *back_chunk = b3d_world_chunk (x, y, z + 1, 0);

#define GET_NEIGHBOURS(c, x,y,z) \
  b3d_cell *top   = b3d_world_chunk_neighbour_cell (c, x, y + 1, z, top_chunk); \
  b3d_cell *bot   = b3d_world_chunk_neighbour_cell (c, x, y - 1, z, bot_chunk); \
  b3d_cell *left  = b3d_world_chunk_neighbour_cell (c, x - 1, y, z, left_chunk); \
  b3d_cell *right = b3d_world_chunk_neighbour_cell (c, x + 1, y, z, right_chunk); \
  b3d_cell *front = b3d_world_chunk_neighbour_cell (c, x, y, z - 1, front_chunk); \
  b3d_cell *back  = b3d_world_chunk_neighbour_cell (c, x, y, z + 1, back_chunk);


#define GET_LOCAL_NEIGHBOURS(c, x,y,z) \
  b3d_cell *top   = b3d_world_chunk_neighbour_cell (c, x, y + 1, z, 0); \
  b3d_cell *bot   = b3d_world_chunk_neighbour_cell (c, x, y - 1, z, 0); \
  b3d_cell *left  = b3d_world_chunk_neighbour_cell (c, x - 1, y, z, 0); \
  b3d_cell *right = b3d_world_chunk_neighbour_cell (c, x + 1, y, z, 0); \
  b3d_cell *front = b3d_world_chunk_neighbour_cell (c, x, y, z - 1, 0); \
  b3d_cell *back  = b3d_world_chunk_neighbour_cell (c, x, y, z + 1, 0);

void b3d_world_chunk_calc_visibility (b3d_chunk *chnk)
{
  int x, y, z;
  for (z = 0; z < CHUNK_SIZE; z++)
    for (y = 0; y < CHUNK_SIZE; y++)
      for (x = 0; x < CHUNK_SIZE; x++)
        {
          unsigned int offs = REL_POS2OFFS (x, y, z);
          chnk->cells[offs].visible = 0;
        }

  int cnt, cnt2;
  for (z = 0; z < CHUNK_SIZE; z++)
    for (y = 0; y < CHUNK_SIZE; y++)
      for (x = 0; x < CHUNK_SIZE; x++)
        {
          b3d_cell *cell = &(chnk->cells[REL_POS2OFFS(x,y,z)]);
          if (cell->type == 0)
            continue;

          // afraid of slowness to not use GET_NEIGHBOURS...
          GET_LOCAL_NEIGHBOURS(chnk, x, y, z);
          if (b3d_world_cell_transparent (top))
            { cell->visible = 1; continue; }
          if (b3d_world_cell_transparent (bot))
            { cell->visible = 1; continue; }
          if (b3d_world_cell_transparent (left))
            { cell->visible = 1; continue; }
          if (b3d_world_cell_transparent (right))
            { cell->visible = 1; continue; }
          if (b3d_world_cell_transparent (front))
            { cell->visible = 1; continue; }
          if (b3d_world_cell_transparent (back))
            { cell->visible = 1; continue; }
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
          assert (len > (offs * 4) + 3);
          b3d_set_cell_from_data (&(chnk->cells[offs]), data + (offs * 4));
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
  // FIXME: we need probably feedback in query_context, in
  //        case this chunk is loaded there!
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
