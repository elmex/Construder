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
#include <SDL_opengl.h>

/* This file contains C utility functions to render
 * the voxel world and the small voxely models.
 */

double ctr_ambient_light = 0.1;

// Vertex indices of a cube built from triangles:
unsigned int quad_vert_idx_tri[6][6] = {
  {0, 1, 2,  2, 3, 0},
  {1, 5, 6,  6, 2, 1},
  {7, 6, 5,  5, 4, 7},
  {4, 5, 1,  1, 0, 4},
  {3, 2, 6,  6, 7, 3},
  {3, 7, 4,  4, 0, 3},
};

// Possible vertexes in a cube:
double quad_vert[8][3] = {
  { 0, 0, 0 },
  { 0, 1, 0 },
  { 1, 1, 0 },
  { 1, 0, 0 },

  { 0, 0, 1 },
  { 0, 1, 1 },
  { 1, 1, 1 },
  { 1, 0, 1 },
};

/* The tint color mapping. The lower nibble of an "add" field of a
 * block is used as index into this array.
 */
double clr_map[16][3] = {
   { 1,   1,   1   },
   { 0.6, 0.6, 0.6 },
   { 0.3, 0.3, 0.3 },

   { 0,   0,   1   },
   { 0,   1,   0   },
   { 1,   0,   0   },

   { 0.3, 0.3, 1   },
   { 0.3, 1,   0.3 },
   { 0.3, 1,   1   },
   { 1,   0.3, 1   },
   { 1,   1,   0.3 },

   { 0.6, 0.6, 1   },
   { 0.6, 1,   0.6 },
   { 0.6, 1,   1   },
   { 1,   0.6, 1   },
   { 1,   1,   0.6 },

};

// NOTE: some combinations of these two variables are not implemented:
#ifndef _WIN32
#define USE_VBO 0
#define USE_SINGLE_BUFFER 0
#else
#define USE_VBO 0
#define USE_SINGLE_BUFFER 0
#endif

#define VERT_P_PRIM 6

#define VERTEXES_SIZE (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE * 6 * VERT_P_PRIM * 3)
#define COLORS_SIZE VERTEXES_SIZE
#define UVS_SIZE (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE * 6 * VERT_P_PRIM * 2)
#define IDX_SIZE (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE * 6 * VERT_P_PRIM)
#define GEOM_SIZE (VERTEXES_SIZE + COLORS_SIZE + UVS_SIZE)

/* Dynamic buffer implementation for storing the data that is
 * to be sent to the gfx card later.
 */
typedef struct _ctr_dyn_buf {
    GLfloat **ptr;
    unsigned int alloc;
    unsigned int item;
} ctr_dyn_buf;

void ctr_dyn_buf_init (ctr_dyn_buf *db, GLfloat **ptr, unsigned int pa_items,
                       unsigned int item_size)
{
  db->ptr = ptr;
  *(db->ptr) = safemalloc (pa_items * item_size);
  db->item = item_size;
  db->alloc = pa_items;
}

void ctr_dyn_buf_grow (ctr_dyn_buf *db, unsigned int items)
{
  if (db->alloc >= items)
    return;

  items *= 2;

  void *nb = safemalloc (items * db->item);
  memcpy (nb, *(db->ptr), db->alloc * db->item);
  free (*(db->ptr));
  *(db->ptr) = nb;
  db->alloc = items;
}

void ctr_dyn_buf_free (ctr_dyn_buf *db)
{
  free (*(db->ptr));
}

/* The main data structure that holds the information to
 * render a chunk or smaller units in the game (for example
 * the models in the slot-bar)
 */
typedef struct _ctr_render_geom {

  // Buffers holding the information:
#if USE_SINGLE_BUFFER
  ctr_dyn_buf db_geom;
  GLfloat *geom;
#else
  ctr_dyn_buf db_vertexes;
  ctr_dyn_buf db_colors;
  ctr_dyn_buf db_uvs;
  GLfloat *vertexes;
  GLfloat *colors;
  GLfloat *uvs;
#endif

  // Buffer holding the indices to the triangles:
  GLuint    vertex_idx[IDX_SIZE];
  int       vertex_idxs;

  // Length of stored data:
  int geom_len;
  int vertexes_len;
  int colors_len;
  int uvs_len;

  GLuint dl;       // Holds the display list id that might be used.
  GLuint geom_buf; // Holds the VBO id when USE_SINGLE_BUFFER is used.
  GLuint vbo_verts, vbo_colors, vbo_uvs, vbo_vert_idxs; // Other VBO ids.

  // Dirty flags:
  int    data_dirty;
  int    dl_dirty;

  // Offset of the rendered data:
  int    xoff, yoff, zoff;
} ctr_render_geom;

void ctr_render_clear_geom (void *c)
{
  ctr_render_geom *geom = c;
  geom->data_dirty = 1;
  geom->vertex_idxs = 0;
  geom->vertexes_len = 0;
  geom->colors_len = 0;
  geom->uvs_len = 0;
  geom->geom_len = 0;
  geom->xoff = 0;
  geom->yoff = 0;
  geom->zoff = 0;
}

static int cgeom = 0;

// FIXME: this should be dependend on the visible radisu, so we maybe want to change
//        this value dynamically adaptively to the current usage.
#define GEOM_PRE_ALLOC 150 // enought for radius of 3 (~93 visible chunks)
static ctr_render_geom *geom_pre_alloc[GEOM_PRE_ALLOC];
static int              geom_last_free = 0;

void *ctr_render_new_geom ()
{
  ctr_render_geom *c = 0;

  if (geom_last_free > 0)
    {
      c = geom_pre_alloc[geom_last_free - 1];
      geom_last_free--;
    }
  else
    {
      c = safemalloc (sizeof (ctr_render_geom));
      cgeom++;
      memset (c, 0, sizeof (ctr_render_geom));
      c->dl = glGenLists (1);

      int i;
      for (i = 0; i < IDX_SIZE; i++)
        c->vertex_idx[i] = i;

#if USE_VBO

#if USE_SINGLE_BUFFER
      ctr_dyn_buf_init (&c->db_geom, (void **) &c->geom, 10, sizeof (GLfloat));
      glGenBuffers (1, &c->geom_buf);

      glBindBuffer (GL_ARRAY_BUFFER, c->geom_buf);
      glBufferData(GL_ARRAY_BUFFER, GEOM_SIZE, NULL, GL_DYNAMIC_DRAW);
#else
      ctr_dyn_buf_init (&c->db_vertexes, &c->vertexes, 10, sizeof (GLfloat));
      ctr_dyn_buf_init (&c->db_colors,   &c->colors,   10, sizeof (GLfloat));
      ctr_dyn_buf_init (&c->db_uvs,      &c->uvs,      10, sizeof (GLfloat));

      glGenBuffers (1, &c->vbo_verts);
      glGenBuffers (1, &c->vbo_colors);
      glGenBuffers (1, &c->vbo_uvs);

      glBindBuffer (GL_ARRAY_BUFFER, c->vbo_verts);
      glBufferData(GL_ARRAY_BUFFER, VERTEXES_SIZE, NULL, GL_DYNAMIC_DRAW);

      glBindBuffer (GL_ARRAY_BUFFER, c->vbo_colors);
      glBufferData(GL_ARRAY_BUFFER, COLORS_SIZE, NULL, GL_DYNAMIC_DRAW);

      glBindBuffer (GL_ARRAY_BUFFER, c->vbo_uvs);
      glBufferData(GL_ARRAY_BUFFER, UVS_SIZE, NULL, GL_DYNAMIC_DRAW);
#endif

      glGenBuffers (1, &c->vbo_vert_idxs);
      glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, c->vbo_vert_idxs);
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof (c->vertex_idx), c->vertex_idx, GL_STATIC_DRAW);
#else
      ctr_dyn_buf_init (&c->db_vertexes, &c->vertexes, 10, sizeof (GLfloat));
      ctr_dyn_buf_init (&c->db_colors,   &c->colors,   10, sizeof (GLfloat));
      ctr_dyn_buf_init (&c->db_uvs,      &c->uvs,      10, sizeof (GLfloat));
#endif

      ctr_render_clear_geom (c);
    }

  c->dl_dirty = 1;

  //d// printf ("geoms allocated: %d x %d (prealloc %d)\n", cgeom, sizeof (ctr_render_geom), geom_last_free);
  return c;
}

void ctr_render_free_geom (void *c)
{
  if (geom_last_free < GEOM_PRE_ALLOC)
    geom_pre_alloc[geom_last_free++] = c;
  else
    {
      ctr_render_geom *geom = c;
      glDeleteLists (geom->dl, 1);
#if USE_VBO
# if USE_SINGLE_BUFFER
      ctr_dyn_buf_free (&geom->db_geom);
      glDeleteBuffers (1, &geom->geom_buf);
# else
      ctr_dyn_buf_free (&geom->db_vertexes);
      ctr_dyn_buf_free (&geom->db_colors);
      ctr_dyn_buf_free (&geom->db_uvs);
      glDeleteBuffers (1, &geom->vbo_verts);
      glDeleteBuffers (1, &geom->vbo_colors);
      glDeleteBuffers (1, &geom->vbo_uvs);
# endif
      glDeleteBuffers (1, &geom->vbo_vert_idxs);
#else
      ctr_dyn_buf_free (&geom->db_vertexes);
      ctr_dyn_buf_free (&geom->db_colors);
      ctr_dyn_buf_free (&geom->db_uvs);
#endif
      safefree (geom);
      cgeom--;
    }
}

// Global renderer init function. Just pre allocates stuff for now.
void ctr_render_init ()
{
  geom_last_free = 0;

  int i;
  for (i = 0; i < GEOM_PRE_ALLOC; i++)
    geom_pre_alloc[i] = ctr_render_new_geom ();

  geom_last_free = GEOM_PRE_ALLOC;
}

// Uploads the data in the geom structure to the graphics card.
void ctr_render_compile_geom (void *c)
{
  ctr_render_geom *geom = c;

#if USE_VBO
# if USE_SINGLE_BUFFER
  glBindBuffer (GL_ARRAY_BUFFER, geom->geom_buf);
  glBufferData(GL_ARRAY_BUFFER, sizeof (GL_FLOAT) * geom->geom_len, geom->geom, GL_DYNAMIC_DRAW);
# else
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_verts);
  glBufferData(GL_ARRAY_BUFFER, sizeof (GL_FLOAT) * geom->vertexes_len, geom->vertexes, GL_DYNAMIC_DRAW);
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_colors);
  glBufferData(GL_ARRAY_BUFFER, sizeof (GL_FLOAT) * geom->colors_len, geom->colors, GL_DYNAMIC_DRAW);
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_uvs);
  glBufferData(GL_ARRAY_BUFFER, sizeof (GL_FLOAT) * geom->uvs_len, geom->uvs, GL_DYNAMIC_DRAW);
# endif
#else
  if (geom->data_dirty)
    {
      ctr_render_geom *geom = c;
      glNewList (geom->dl, GL_COMPILE);
      glEnableClientState(GL_VERTEX_ARRAY);
      glEnableClientState(GL_COLOR_ARRAY);
      glEnableClientState(GL_TEXTURE_COORD_ARRAY);

      glVertexPointer   (3, GL_FLOAT, 0, geom->vertexes);
      glColorPointer    (3, GL_FLOAT, 0, geom->colors);
      glTexCoordPointer (2, GL_FLOAT, 0, geom->uvs);

      glDrawElements (GL_TRIANGLES, geom->vertex_idxs, GL_UNSIGNED_INT, geom->vertex_idx);

      glDisableClientState(GL_TEXTURE_COORD_ARRAY);
      glDisableClientState(GL_COLOR_ARRAY);
      glDisableClientState(GL_VERTEX_ARRAY);

      glEndList ();
    }
#endif

  geom->data_dirty = 0;
  geom->dl_dirty = 0;
}

// Draws the data that was uploaded to the graphics card earlier.
void ctr_render_draw_geom (void *c)
{
  ctr_render_geom *geom = c;

#if USE_VBO
# if USE_SINGLE_BUFFER
  glBindBuffer (GL_ARRAY_BUFFER, geom->geom_buf);
  glEnableClientState(GL_VERTEX_ARRAY);
  glEnableClientState(GL_COLOR_ARRAY);
  glEnableClientState(GL_TEXTURE_COORD_ARRAY);
  glVertexPointer   (3, GL_FLOAT, 8 * sizeof (GLfloat), 0);
  glColorPointer    (3, GL_FLOAT, 8 * sizeof (GLfloat), (void *) (3 * sizeof (GLfloat)));
  glTexCoordPointer (2, GL_FLOAT, 8 * sizeof (GLfloat), (void *) (6 * sizeof (GLfloat)));
# else
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_verts);
  glEnableClientState(GL_VERTEX_ARRAY);
  glVertexPointer (3, GL_FLOAT, 0, 0);

  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_colors);
  glEnableClientState(GL_COLOR_ARRAY);
  glColorPointer    (3, GL_FLOAT, 0, 0);

  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_uvs);
  glEnableClientState(GL_TEXTURE_COORD_ARRAY);
  glTexCoordPointer (2, GL_FLOAT, 0, 0);
# endif

  glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, geom->vbo_vert_idxs);
  glDrawElements (GL_TRIANGLES, geom->vertex_idxs, GL_UNSIGNED_INT, 0);

  glDisableClientState(GL_TEXTURE_COORD_ARRAY);
  glDisableClientState(GL_COLOR_ARRAY);
  glDisableClientState(GL_VERTEX_ARRAY);

#else
  if (geom->data_dirty || geom->dl_dirty)
    ctr_render_compile_geom (geom);
  glCallList (geom->dl);
#endif

}

// Ads one face of a cube to the geom data structure.
void ctr_render_add_face (unsigned int face, unsigned int type, unsigned short color, double light,
                          double xoffs, double yoffs, double zoffs,
                          double scale,
                          double xsoffs, double ysoffs, double zsoffs,
                          ctr_render_geom *geom)
{
  //d// printf ("RENDER FACE %d: %g %g %g %g\n", type, xoffs, yoffs, zoffs);
  ctr_obj_attr *oa = ctr_world_get_attr (type);
  double *uv = &(oa->uv[0]);

  int h, j, k;
#if USE_SINGLE_BUFFER
  ctr_dyn_buf_grow (&geom->db_geom, geom->geom_len + 12 * 3 + 6 * 2);
#else
  ctr_dyn_buf_grow (&geom->db_vertexes, geom->vertexes_len + 6 * 3);
#endif
  for (h = 0; h < 6; h++)
    {
      double *vert = &(quad_vert[quad_vert_idx_tri[face][h]][0]);

#if USE_SINGLE_BUFFER
      geom->geom[geom->geom_len++] = ((vert[0] + xoffs) * scale) + xsoffs;
      geom->geom[geom->geom_len++] = ((vert[1] + yoffs) * scale) + ysoffs;
      geom->geom[geom->geom_len++] = ((vert[2] + zoffs) * scale) + zsoffs;

      geom->geom[geom->geom_len++] = clr_map[(color & 0xF)][0] * light;
      geom->geom[geom->geom_len++] = clr_map[(color & 0xF)][1] * light;
      geom->geom[geom->geom_len++] = clr_map[(color & 0xF)][2] * light;

      if (h == 0)
        {
          geom->geom[geom->geom_len++] = uv[2];
          geom->geom[geom->geom_len++] = uv[3];
        }

      if (h == 1)
        {
          geom->geom[geom->geom_len++] = uv[2];
          geom->geom[geom->geom_len++] = uv[1];
        }

      if (h == 2)
        {
          geom->geom[geom->geom_len++] = uv[0];
          geom->geom[geom->geom_len++] = uv[1];
        }

      if (h == 3)
        {
          geom->geom[geom->geom_len++] = uv[0];
          geom->geom[geom->geom_len++] = uv[1];
        }

      if (h == 4)
        {
          geom->geom[geom->geom_len++] = uv[0];
          geom->geom[geom->geom_len++] = uv[3];
        }

      if (h == 5)
        {
          geom->geom[geom->geom_len++] = uv[2];
          geom->geom[geom->geom_len++] = uv[3];
        }
# else
      geom->vertexes[geom->vertexes_len++] = ((vert[0] + xoffs) * scale) + xsoffs;
      geom->vertexes[geom->vertexes_len++] = ((vert[1] + yoffs) * scale) + ysoffs;
      geom->vertexes[geom->vertexes_len++] = ((vert[2] + zoffs) * scale) + zsoffs;
# endif

      geom->vertex_idxs++;
    }

#if !USE_SINGLE_BUFFER
  ctr_dyn_buf_grow (&geom->db_colors, geom->colors_len + VERT_P_PRIM * 3);
  ctr_dyn_buf_grow (&geom->db_uvs,    geom->uvs_len    + VERT_P_PRIM * 2);

  for (h = 0; h < VERT_P_PRIM; h++)
    {
      geom->colors[geom->colors_len++] = clr_map[(color & 0xF)][0] * light;
      geom->colors[geom->colors_len++] = clr_map[(color & 0xF)][1] * light;
      geom->colors[geom->colors_len++] = clr_map[(color & 0xF)][2] * light;
    }

  geom->uvs[geom->uvs_len++] = uv[2];
  geom->uvs[geom->uvs_len++] = uv[3];

  geom->uvs[geom->uvs_len++] = uv[2];
  geom->uvs[geom->uvs_len++] = uv[1];

  geom->uvs[geom->uvs_len++] = uv[0];
  geom->uvs[geom->uvs_len++] = uv[1];

  geom->uvs[geom->uvs_len++] = uv[0];
  geom->uvs[geom->uvs_len++] = uv[1];

  geom->uvs[geom->uvs_len++] = uv[0];
  geom->uvs[geom->uvs_len++] = uv[3];

  geom->uvs[geom->uvs_len++] = uv[2];
  geom->uvs[geom->uvs_len++] = uv[3];

#endif
}

/* Renders a "model", which is defined by it's dimension
 * (size of a cube it fits in) and the offset within that cube.
 *
 * The models need to be sent to C before they can be used.
 * See also ctr_world_get_attr ().
 */
void ctr_render_model (unsigned int type, unsigned short color, double light, double xo, double yo, double zo, void *chnk, int skip, int force_model, double scaling);
void ctr_render_model (unsigned int type, unsigned short color, double light, double xo, double yo, double zo, void *chnk, int skip, int force_model, double scaling)
{
  ctr_obj_attr *oa = ctr_world_get_attr (type);
  unsigned int dim = oa->model_dim;
  unsigned int *blocks = &(oa->model_blocks[0]);

  if (!oa->model || (oa->has_txt && !force_model))
    {
      /* Used in two circumstances:
       *   - no model for the block type present.
       *   - force_model is disabled and the block type has a texture.
       */

      blocks = &type;
      dim = 1;
    }

  int x, y, z;
  unsigned int blk_offs = 0;
  double scale = (double) 1 / (double) (dim > 0 ? dim : 1);
  scale *= scaling;

  int drawn = 0;
  //d//  printf ("RENDER MODEL START %d %f %f %f\n", dim, xo, yo, zo);
  for (y = 0; y < dim; y++)
    for (z = 0; z < dim; z++)
      for (x = dim - 1; x >= 0; x--)
        {
          unsigned int blktype = blocks[blk_offs];
          ctr_obj_attr *oa = ctr_world_get_attr (blktype);
         //d//  printf ("RENDER MODEL %d: %d\n", blk_offs, blktype);

          if (blktype == 0) // was: oa->transparent, but models are transp. too
            {
              blk_offs++;
              continue;
            }


          //d// printf ("MODEL FACE %f %f %f :%d %g\n", (double) x + xo, (double) y + yo, (double) z + zo, blktype, scale);
          if (!oa->has_txt && oa->model)
            {
              // Attention: Possible endless recursion :-)
              ctr_render_model (
                blktype, color, light,
                ((double) x * scale) + xo,
                ((double) y * scale) + yo,
                ((double) z * scale) + zo, chnk, -1, 0, scale);
            }
          else if (oa->has_txt)
            {
              int face;
              for (face = 0; face < 6; face++)
                ctr_render_add_face (
                  face, blktype, color, light,
                  x, y, z, scale,
                  xo, yo, zo,
                  chnk);
            }

          drawn++;
          /* The skip is used for drawing only a part of the model.
           * This is used in the material view to document how a model is built.
           */
          if (skip >= 0 && drawn >= skip)
            goto end;
          blk_offs++;
        }
  end:
    return;
}

// Computes the light of a cell.
double ctr_cell_light (ctr_cell *c)
{
  double light = (double) c->light / 15;
  if (light < ctr_ambient_light)
    light = ctr_ambient_light;
  return light;
}

/* Computes the data that is sent to OpenGL later from the
 * given chunk coordinates.
 */
int ctr_render_chunk (int x, int y, int z, void *geom)
{
  ctr_chunk *c = ctr_world_chunk (x, y, z, 0);
  if (!c)
    return 0;

  LOAD_NEIGHBOUR_CHUNKS(x,y,z);

  ctr_render_geom *g = geom;
  g->xoff = x * CHUNK_SIZE;
  g->yoff = y * CHUNK_SIZE;
  g->zoff = z * CHUNK_SIZE;

  //d// ctr_world_chunk_calc_visibility (c);

  int ix, iy, iz;
  for (iz = 0; iz < CHUNK_SIZE; iz++)
    for (iy = 0; iy < CHUNK_SIZE; iy++)
      for (ix = 0; ix < CHUNK_SIZE; ix++)
        {
          int dx = ix + g->xoff;
          int dy = iy + g->yoff;
          int dz = iz + g->zoff;

          ctr_cell *cur = ctr_world_chunk_neighbour_cell (c, ix, iy, iz, 0);
          if (!cur->visible)// || ctr_world_cell_transparent (cur))
            continue;

          ctr_obj_attr *oa = ctr_world_get_attr (cur->type);
          if (!oa->has_txt)
            {
              // blocks without texture probably have a model:
              ctr_render_model (
                cur->type, cur->add & 0x0F, ctr_cell_light (cur), dx, dy, dz, geom, -1, 0, 1);
              continue;
            }

          GET_NEIGHBOURS(c, ix, iy, iz);

          if (ctr_world_cell_transparent (front))
            ctr_render_add_face (
              0, cur->type, cur->add & 0x0F, ctr_cell_light (front),
              dx, dy, dz, 1, 0, 0, 0, geom);

          if (ctr_world_cell_transparent (top))
            ctr_render_add_face (
              1, cur->type, cur->add & 0x0F, ctr_cell_light (top),
              dx, dy, dz, 1, 0, 0, 0, geom);

          if (ctr_world_cell_transparent (back))
            ctr_render_add_face (
              2, cur->type, cur->add & 0x0F, ctr_cell_light (back),
              dx, dy, dz, 1, 0, 0, 0, geom);

          if (ctr_world_cell_transparent (left))
            ctr_render_add_face (
              3, cur->type, cur->add & 0x0F, ctr_cell_light (left),
              dx, dy, dz, 1, 0, 0, 0, geom);

          if (ctr_world_cell_transparent (right))
            ctr_render_add_face (
              4, cur->type, cur->add & 0x0F, ctr_cell_light (right),
              dx, dy, dz, 1, 0, 0, 0, geom);

          if (ctr_world_cell_transparent (bot))
            ctr_render_add_face (
              5, cur->type, cur->add & 0x0F, ctr_cell_light (bot),
              dx, dy, dz, 1, 0, 0, 0, geom);
        }

  ctr_render_compile_geom (geom);
  return 1;
}
