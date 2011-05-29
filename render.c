#include <SDL_opengl.h>

unsigned int quad_vert_idx[6][4] = {
  {0, 1, 2, 3},
  {1, 5, 6, 2},
  {7, 6, 5, 4},
  {4, 5, 1, 0},
  {3, 2, 6, 7},
  {3, 7, 4, 0},
};

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

typedef struct _ctr_render_geom {
  GLfloat  vertexes  [CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE * 6 * 4 * 3];
  GLfloat  colors    [CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE * 6 * 4 * 3];
  GLfloat  uvs       [CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE * 6 * 4 * 2];
  GLuint    vertex_idx[CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE * 6 * 4];
  int       vertex_idxs;

  int       vertexes_len;
  int       colors_len;
  int       uvs_len;

  GLuint dl;
  GLuint vbo_verts, vbo_colors, vbo_uvs, vbo_vert_idxs;
  int    data_dirty;
  int    dl_dirty;

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
  geom->xoff = 0;
  geom->yoff = 0;
  geom->zoff = 0;
}

static int cgeom = 0;

#define GEOM_PRE_ALLOC 200
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
      c = malloc (sizeof (ctr_render_geom));
      memset (c, 0, sizeof (ctr_render_geom));
      c->dl = glGenLists (1);
      glGenBuffers (1, &c->vbo_verts);
      glGenBuffers (1, &c->vbo_colors);
      glGenBuffers (1, &c->vbo_uvs);
      glGenBuffers (1, &c->vbo_vert_idxs);

      glBindBuffer (GL_ARRAY_BUFFER, c->vbo_verts);
      glBufferData(GL_ARRAY_BUFFER, sizeof (c->vertexes), NULL, GL_DYNAMIC_DRAW);

      glBindBuffer (GL_ARRAY_BUFFER, c->vbo_colors);
      glBufferData(GL_ARRAY_BUFFER, sizeof (c->colors), NULL, GL_DYNAMIC_DRAW);

      glBindBuffer (GL_ARRAY_BUFFER, c->vbo_uvs);
      glBufferData(GL_ARRAY_BUFFER, sizeof (c->uvs), NULL, GL_DYNAMIC_DRAW);

      int i;
      for (i = 0; i < CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE * 6 * 4; i++)
        c->vertex_idx[i] = i;

      glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, c->vbo_vert_idxs);
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof (c->vertex_idx), c->vertex_idx, GL_DYNAMIC_DRAW);

      ctr_render_clear_geom (c);
    }

  c->dl_dirty = 1;

  cgeom++;
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
      glDeleteBuffers (1, &geom->vbo_verts);
      glDeleteBuffers (1, &geom->vbo_colors);
      glDeleteBuffers (1, &geom->vbo_uvs);
      glDeleteBuffers (1, &geom->vbo_vert_idxs);
      free (geom);
    }

  cgeom--;
}

void ctr_render_init ()
{
  geom_last_free = 0;

  int i;
  for (i = 0; i < GEOM_PRE_ALLOC; i++)
    geom_pre_alloc[i] = ctr_render_new_geom ();

  geom_last_free = GEOM_PRE_ALLOC;
}

void ctr_render_compile_geom (void *c)
{
  ctr_render_geom *geom = c;

#if 1
# if 0
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_verts);
  glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof (GL_FLOAT) * geom->vertexes_len, geom->vertexes);
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_colors);
  glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof (GL_FLOAT) * geom->colors_len, geom->colors);
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_uvs);
  glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof (GL_FLOAT) * geom->uvs_len, geom->uvs);
#else
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_verts);
  glBufferData(GL_ARRAY_BUFFER, sizeof (GL_FLOAT) * geom->vertexes_len, geom->vertexes, GL_DYNAMIC_DRAW);
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_colors);
  glBufferData(GL_ARRAY_BUFFER, sizeof (GL_FLOAT) * geom->colors_len, geom->colors, GL_DYNAMIC_DRAW);
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_uvs);
  glBufferData(GL_ARRAY_BUFFER, sizeof (GL_FLOAT) * geom->uvs_len, geom->uvs, GL_DYNAMIC_DRAW);
#endif

# if 0
  if (geom->data_dirty)
    {
      glNewList (geom->dl, GL_COMPILE);
      glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_verts);
      glEnableClientState(GL_VERTEX_ARRAY);
      glVertexPointer (3, GL_FLOAT, 0, 0);

      glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_colors);
      glEnableClientState(GL_COLOR_ARRAY);
      glColorPointer    (3, GL_FLOAT, 0, 0);

      glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_uvs);
      glEnableClientState(GL_TEXTURE_COORD_ARRAY);
      glTexCoordPointer (2, GL_FLOAT, 0, 0);

      glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, geom->vbo_vert_idxs);
      glDrawElements (GL_QUADS, geom->vertex_idxs, GL_UNSIGNED_INT, 0);

      glDisableClientState(GL_TEXTURE_COORD_ARRAY);
      glDisableClientState(GL_COLOR_ARRAY);
      glDisableClientState(GL_VERTEX_ARRAY);
      glEndList ();
    }
# endif

#else
  ctr_render_geom *geom = c;
  glNewList (geom->dl, GL_COMPILE);
  //glPushMatrix ();
  //glTranslatef (geom->xoff, geom->yoff, geom->zoff);
  glEnableClientState(GL_VERTEX_ARRAY);
  glEnableClientState(GL_COLOR_ARRAY);
  glEnableClientState(GL_TEXTURE_COORD_ARRAY);

  glVertexPointer   (3, GL_FLOAT, 0, geom->vertexes);
  glColorPointer    (3, GL_FLOAT, 0, geom->colors);
  glTexCoordPointer (2, GL_FLOAT, 0, geom->uvs);

  glDrawElements (GL_QUADS, geom->vertex_idxs, GL_UNSIGNED_INT, geom->vertex_idx);

  glDisableClientState(GL_TEXTURE_COORD_ARRAY);
  glDisableClientState(GL_COLOR_ARRAY);
  glDisableClientState(GL_VERTEX_ARRAY);

  //glPopMatrix ();
  glEndList ();
#endif

  geom->data_dirty = 0;
  geom->dl_dirty = 0;
}

void ctr_render_draw_geom (void *c)
{
  ctr_render_geom *geom = c;

#if 1
  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_verts);
  glEnableClientState(GL_VERTEX_ARRAY);
  glVertexPointer (3, GL_FLOAT, 0, 0);

  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_colors);
  glEnableClientState(GL_COLOR_ARRAY);
  glColorPointer    (3, GL_FLOAT, 0, 0);

  glBindBuffer (GL_ARRAY_BUFFER, geom->vbo_uvs);
  glEnableClientState(GL_TEXTURE_COORD_ARRAY);
  glTexCoordPointer (2, GL_FLOAT, 0, 0);

  glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, geom->vbo_vert_idxs);
  glDrawElements (GL_QUADS, geom->vertex_idxs, GL_UNSIGNED_INT, 0);

  glDisableClientState(GL_TEXTURE_COORD_ARRAY);
  glDisableClientState(GL_COLOR_ARRAY);
  glDisableClientState(GL_VERTEX_ARRAY);

#else

  if (geom->data_dirty || geom->dl_dirty)
    ctr_render_compile_geom (geom);
#endif

  glCallList (geom->dl);
}

void
ctr_render_add_face (unsigned int face, unsigned int type, double light,
                     double xoffs, double yoffs, double zoffs,
                     double scale,
                     double xsoffs, double ysoffs, double zsoffs,
                     ctr_render_geom *geom)
{
  //d// printf ("RENDER FACE %d: %g %g %g %g\n", type, xoffs, yoffs, zoffs);
  int h, j, k;
  for (h = 0; h < 4; h++)
    {
      double *vert = &(quad_vert[quad_vert_idx[face][h]][0]);
      geom->vertexes[geom->vertexes_len++] = ((vert[0] + xoffs) * scale) + xsoffs;
      geom->vertexes[geom->vertexes_len++] = ((vert[1] + yoffs) * scale) + ysoffs;
      geom->vertexes[geom->vertexes_len++] = ((vert[2] + zoffs) * scale) + zsoffs;
      geom->vertex_idxs++;
    }

  for (h = 0; h < 12; h++)
    geom->colors[geom->colors_len++] = light;

  ctr_obj_attr *oa = ctr_world_get_attr (type);
  double *uv = &(oa->uv[0]);

  geom->uvs[geom->uvs_len++] = uv[2];
  geom->uvs[geom->uvs_len++] = uv[3];

  geom->uvs[geom->uvs_len++] = uv[2];
  geom->uvs[geom->uvs_len++] = uv[1];

  geom->uvs[geom->uvs_len++] = uv[0];
  geom->uvs[geom->uvs_len++] = uv[1];

  geom->uvs[geom->uvs_len++] = uv[0];
  geom->uvs[geom->uvs_len++] = uv[3];
}

void
ctr_render_model (unsigned int type, double light, unsigned int xo, unsigned int yo, unsigned int zo, void *chnk)
{
  ctr_obj_attr *oa = ctr_world_get_attr (type);
  unsigned int dim = oa->model_dim;
  unsigned int *blocks = &(oa->model_blocks[0]);

  if (!oa->model)
    {
      blocks = &type;
      dim = 1;
    }

  int x, y, z;
  unsigned int blk_offs = 0;
  double scale = (double) 1 / (double) (dim > 0 ? dim : 1);

  for (y = 0; y < dim; y++)
    for (z = 0; z < dim; z++)
      for (x = 0; x < dim; x++)
        {
          unsigned int blktype = blocks[blk_offs];
          ctr_obj_attr *oa = ctr_world_get_attr (blktype);

          if (oa->transparent)
            continue;
          //d//printf ("MODEL FACE %d %d %d: %d %g\n", x + xo, y + yo, z + zo, blktype, scale);

          int face;
          for (face = 0; face < 6; face++)
            ctr_render_add_face (
              face, blktype, light,
              x, y, z, scale,
              xo, yo, zo,
              chnk);
          blk_offs++;
        }
}

double ctr_cell_light (ctr_cell *c)
{
  double light = (double) c->light / 15;
  if (light < 0.1)
    light = 0.1;
  return light;
}

void
ctr_render_chunk (int x, int y, int z, void *geom)
{
  ctr_chunk *c = ctr_world_chunk (x, y, z, 0);
  if (!c)
    return;

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

//         printf ("OFFS %d %d %d \n", ix, iy, iz);
          ctr_cell *cur = ctr_world_chunk_neighbour_cell (c, ix, iy, iz, 0);
          if (!cur->visible)// || ctr_world_cell_transparent (cur))
            continue;

          ctr_obj_attr *oa = ctr_world_get_attr (cur->type);
          if (oa->model)
            {
              ctr_render_model (
                cur->type, ctr_cell_light (cur), dx, dy, dz, geom);
              continue;
            }

          GET_NEIGHBOURS(c, ix, iy, iz);

          if (ctr_world_cell_transparent (front))
            ctr_render_add_face (
              0, cur->type, ctr_cell_light (front), dx, dy, dz, 1, 0, 0, 0, geom);

          if (ctr_world_cell_transparent (top))
            ctr_render_add_face (
              1, cur->type, ctr_cell_light (top), dx, dy, dz, 1, 0, 0, 0, geom);

          if (ctr_world_cell_transparent (back))
            ctr_render_add_face (
              2, cur->type, ctr_cell_light (back), dx, dy, dz, 1, 0, 0, 0, geom);

          if (ctr_world_cell_transparent (left))
            ctr_render_add_face (
              3, cur->type, ctr_cell_light (left), dx, dy, dz, 1, 0, 0, 0, geom);

          if (ctr_world_cell_transparent (right))
            ctr_render_add_face (
              4, cur->type, ctr_cell_light (right), dx, dy, dz, 1, 0, 0, 0, geom);

          if (ctr_world_cell_transparent (bot))
            ctr_render_add_face (
              5, cur->type, ctr_cell_light (bot), dx, dy, dz, 1, 0, 0, 0, geom);
        }

  ctr_render_compile_geom (geom);
  return;
}
