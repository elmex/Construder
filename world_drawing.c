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

/* This file implements setting up a "drawing context" over a part of the
 * world. The main purpose is to make sure chunks can be quickly accessed
 * for the mutation operations or the light algorithm.
 */
#define DRAW_CONTEXT_MAX_SIZE (20 * 20 * 20)

typedef struct _ctr_world_query {
    // Chunk coordinates.
    int chnk_x, chnk_y, chnk_z,
        end_chnk_x, end_chnk_y, end_chnk_z;

    // Size of context in chunks.
    int x_w, y_w, z_w;

    // The "loaded" chunks.
    ctr_chunk *chunks[DRAW_CONTEXT_MAX_SIZE];

    // Flag that we tried to fetch chunks from the global data structure.
    int loaded;
} ctr_world_query;

#define QUERY_CHUNK(x,y,z) QUERY_CONTEXT.chunks[x + y * (QUERY_CONTEXT.x_w) + z * (QUERY_CONTEXT.x_w * QUERY_CONTEXT.y_w)]

static ctr_world_query QUERY_CONTEXT;

/* Cleans up the query context after usage and
 * calls change callbacks if needed.
 *
 * no_update == 0 - Call callbacks for every changed/dirty chunk.
 * no_update == 1 - Don't call any callbacks.
 * no_update == 2 - Call callbacks for every chunk in the context.
 */
int ctr_world_query_desetup (int no_update) // no_update == 2 means: force update
{
  int cnt = 0;
  int x, y, z;
  for (z = 0; z < QUERY_CONTEXT.z_w; z++)
    for (y = 0; y < QUERY_CONTEXT.y_w; y++)
      for (x = 0; x < QUERY_CONTEXT.x_w; x++)
        {
          ctr_chunk *chnk = QUERY_CHUNK(x, y, z);
          if (!chnk)
            continue;

          if (no_update == 2)
            {
              ctr_world_emit_chunk_change (
                x + QUERY_CONTEXT.chnk_x,
                y + QUERY_CONTEXT.chnk_y,
                z + QUERY_CONTEXT.chnk_z);
              continue;
            }

          if (!chnk->dirty)
            continue;

          chnk->dirty = 0;
          cnt++;

          if (no_update == 0)
            ctr_world_emit_chunk_change (
              x + QUERY_CONTEXT.chnk_x,
              y + QUERY_CONTEXT.chnk_y,
              z + QUERY_CONTEXT.chnk_z);
        }

  QUERY_CONTEXT.loaded = 0;
  return cnt;
}

void ctr_world_query_setup (int x, int y, int z, int ex, int ey, int ez)
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

// Loads chunks from the global data structure (if available).
void ctr_world_query_load_chunks (int alloc)
{
  int x, y, z;
  for (z = QUERY_CONTEXT.chnk_z; z <= QUERY_CONTEXT.end_chnk_z; z++)
    for (y = QUERY_CONTEXT.chnk_y; y <= QUERY_CONTEXT.end_chnk_y; y++)
      for (x = QUERY_CONTEXT.chnk_x; x <= QUERY_CONTEXT.end_chnk_x; x++)
        {
          int ox = x - QUERY_CONTEXT.chnk_x;
          int oy = y - QUERY_CONTEXT.chnk_y;
          int oz = z - QUERY_CONTEXT.chnk_z;
          ctr_chunk *c = QUERY_CHUNK(ox, oy, oz) = ctr_world_chunk (x, y, z, alloc);
          if (c)
            ctr_chunk_clear_changes (c);
        }
  QUERY_CONTEXT.loaded = 1;
}

// Compute absolute world coordinates from context relative coordinates.
void ctr_world_query_rel2abs (int *rel_x, int *rel_y, int *rel_z)
{
  *rel_x = QUERY_CONTEXT.chnk_x * CHUNK_SIZE + *rel_x;
  *rel_y = QUERY_CONTEXT.chnk_y * CHUNK_SIZE + *rel_y;
  *rel_z = QUERY_CONTEXT.chnk_z * CHUNK_SIZE + *rel_z;
}

// Compute the context relative coordinates from absolute ones.
void ctr_world_query_abs2rel (int *x, int *y, int *z)
{
  vec3_init (pos, *x, *y, *z);
  vec3_s_div (pos, CHUNK_SIZE);
  vec3_floor (pos);
  int chnk_x = pos[0],
      chnk_y = pos[1],
      chnk_z = pos[2];

  *x -= chnk_x * CHUNK_SIZE;
  *y -= chnk_y * CHUNK_SIZE;
  *z -= chnk_z * CHUNK_SIZE;

  chnk_x -= QUERY_CONTEXT.chnk_x;
  chnk_y -= QUERY_CONTEXT.chnk_y;
  chnk_z -= QUERY_CONTEXT.chnk_z;
  assert (chnk_x >= 0);
  assert (chnk_y >= 0);
  assert (chnk_z >= 0);

  *x += chnk_x * CHUNK_SIZE;
  *y += chnk_y * CHUNK_SIZE;
  *z += chnk_z * CHUNK_SIZE;
}

ctr_cell *ctr_world_query_cell_at (unsigned int rel_x, unsigned int rel_y, unsigned int rel_z, int modify)
{
  if (rel_x < 0) return 0;
  if (rel_y < 0) return 0;
  if (rel_z < 0) return 0;

  int chnk_x = rel_x / CHUNK_SIZE,
      chnk_y = rel_y / CHUNK_SIZE,
      chnk_z = rel_z / CHUNK_SIZE;
  int chnk_rel_x = rel_x - chnk_x * CHUNK_SIZE,
      chnk_rel_y = rel_y - chnk_y * CHUNK_SIZE,
      chnk_rel_z = rel_z - chnk_z * CHUNK_SIZE;

  assert (QUERY_CONTEXT.loaded);

  if (chnk_x >= QUERY_CONTEXT.x_w) return 0;
  if (chnk_y >= QUERY_CONTEXT.y_w) return 0;
  if (chnk_z >= QUERY_CONTEXT.z_w) return 0;

  ctr_chunk *chnk = QUERY_CHUNK(chnk_x, chnk_y, chnk_z);
  if (!chnk)
    return 0;

  ctr_cell *c =
    ctr_chunk_cell_at_rel (chnk, chnk_rel_x, chnk_rel_y, chnk_rel_z);

  if (modify)
    chnk->dirty = 1;
    //ctr_chunk_cell_changed (chnk, chnk_rel_x, chnk_rel_y, chnk_rel_z);

  return c;
}

void ctr_world_query_set_at_pl (unsigned int rel_x, unsigned int rel_y, unsigned int rel_z, AV *cell)
{
  ctr_cell *c = ctr_world_query_cell_at (rel_x, rel_y, rel_z, 1);
  if (!c)
    return;

  int otype = c->type;

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

  if (ctr_world_is_active (otype) || ctr_world_is_active (c->type))
    {
      t = av_fetch (cell, 5, 0);
      ctr_world_query_rel2abs (&rel_x, &rel_y, &rel_z);
      ctr_world_emit_active_cell_change (rel_x, rel_y, rel_z, c, t ? *t : 0);
    }
}
