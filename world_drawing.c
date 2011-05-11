
#define DRAW_CONTEXT_MAX_SIZE (20 * 20 * 20)

typedef struct _b3d_world_query {
    int chnk_x, chnk_y, chnk_z,
        end_chnk_x, end_chnk_y, end_chnk_z;
    int x_w, y_w, z_w;
    b3d_chunk *chunks[DRAW_CONTEXT_MAX_SIZE];
    int loaded;
} b3d_world_query;

#define QUERY_CHUNK(x,y,z) QUERY_CONTEXT.chunks[x + y * (QUERY_CONTEXT.x_w) + z * (QUERY_CONTEXT.x_w * QUERY_CONTEXT.y_w)]

static b3d_world_query QUERY_CONTEXT;

void b3d_world_query_desetup ()
{
  int x, y, z;
  for (z = 0; z < QUERY_CONTEXT.x_w; z++)
    for (y = 0; y < QUERY_CONTEXT.y_w; y++)
      for (x = 0; x < QUERY_CONTEXT.z_w; x++)
        {
          // tODO: optimize by dirty flag!
          b3d_world_emit_chunk_change (
            x + QUERY_CONTEXT.chnk_x,
            y + QUERY_CONTEXT.chnk_y,
            z + QUERY_CONTEXT.chnk_z);
        }
  QUERY_CONTEXT.loaded = 0;
}

void b3d_world_query_setup (int x, int y, int z, int ex, int ey, int ez)
{
  if (x > ex) SWAP(int,x,ex);
  if (y > ey) SWAP(int,y,ey);
  if (z > ez) SWAP(int,z,ez);

  QUERY_CONTEXT.chnk_x = x;
  QUERY_CONTEXT.chnk_y = y;
  QUERY_CONTEXT.chnk_z = z;
  QUERY_CONTEXT.end_chnk_x = ex;
  QUERY_CONTEXT.end_chnk_y = ey;
  QUERY_CONTEXT.end_chnk_z = ez;

  QUERY_CONTEXT.x_w = (ex - x) + 1;
  QUERY_CONTEXT.y_w = (ey - y) + 1;
  QUERY_CONTEXT.z_w = (ez - z) + 1;

  QUERY_CONTEXT.loaded = 0;
}

void b3d_world_query_unallocated_chunks (AV *chnkposes)
{
  int x, y, z;
  for (z = QUERY_CONTEXT.chnk_z; z <= QUERY_CONTEXT.end_chnk_z; z++)
    for (y = QUERY_CONTEXT.chnk_y; y <= QUERY_CONTEXT.end_chnk_y; y++)
      for (x = QUERY_CONTEXT.chnk_x; x <= QUERY_CONTEXT.end_chnk_x; x++)
        {
          b3d_chunk *chnk = b3d_world_chunk (x, y, z, 0);
          if (!chnk)
            {
              av_push (chnkposes, newSViv (x));
              av_push (chnkposes, newSViv (y));
              av_push (chnkposes, newSViv (z));
            }
        }
}

void b3d_world_query_load_chunks ()
{
  int x, y, z;
  for (z = QUERY_CONTEXT.chnk_z; z <= QUERY_CONTEXT.end_chnk_z; z++)
    for (y = QUERY_CONTEXT.chnk_y; y <= QUERY_CONTEXT.end_chnk_y; y++)
      for (x = QUERY_CONTEXT.chnk_x; x <= QUERY_CONTEXT.end_chnk_x; x++)
        {
          int ox = x - QUERY_CONTEXT.chnk_x;
          int oy = y - QUERY_CONTEXT.chnk_y;
          int oz = z - QUERY_CONTEXT.chnk_z;
          QUERY_CHUNK(ox, oy, oz) = b3d_world_chunk (x, y, z, 1);
        }
  QUERY_CONTEXT.loaded = 1;
}

void b3d_world_query_set_at (unsigned int rel_x, unsigned int rel_y, unsigned int rel_z, AV *cell)
{
  int chnk_x = rel_x / CHUNK_SIZE,
      chnk_y = rel_y / CHUNK_SIZE,
      chnk_z = rel_z / CHUNK_SIZE;

  assert (QUERY_CONTEXT.loaded);
  assert (chnk_x < QUERY_CONTEXT.x_w);
  assert (chnk_y < QUERY_CONTEXT.y_w);
  assert (chnk_z < QUERY_CONTEXT.z_w);

  b3d_chunk *chnk = QUERY_CHUNK(chnk_x, chnk_y, chnk_z);
  b3d_cell *c =
    b3d_chunk_cell_at_rel (
      chnk,
      rel_x - chnk_x * CHUNK_SIZE,
      rel_y - chnk_y * CHUNK_SIZE,
      rel_z - chnk_z * CHUNK_SIZE);

  SV **t = av_fetch (cell, 0, 0);
  if (t) c->type = SvIV (*t);

  t = av_fetch (cell, 1, 0);
  if (t) c->light = SvIV (*t);

  t = av_fetch (cell, 2, 0);
  if (t) c->meta = SvIV (*t);

  t = av_fetch (cell, 3, 0);
  if (t) c->add = SvIV (*t);

  t = av_fetch (cell, 4, 0);
  if (t) c->visible = SvIV (*t);
}
