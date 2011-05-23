// my @indices  = (
//    qw/ 0 1 2 3 /, # 0 front
//    qw/ 1 5 6 2 /, # 1 top
//    qw/ 7 6 5 4 /, # 2 back
//    qw/ 4 5 1 0 /, # 3 left
//    qw/ 3 2 6 7 /, # 4 right
//    qw/ 3 7 4 0 /, # 5 bottom
// );
// 
// my @vertices = (
//    [ 0,  0,  0 ],
//    [ 0,  1,  0 ],
//    [ 1,  1,  0 ],
//    [ 1,  0,  0 ],
// 
//    [ 0,  0,  1 ],
//    [ 0,  1,  1 ],
//    [ 1,  1,  1 ],
//    [ 1,  0,  1 ],
// );


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

/*
   my $quad_cnt;
   FACES:
   for (my $z = 0; $z < $CHNK_SIZE; $z++) {
      for (my $y = 0; $y < $CHNK_SIZE; $y++) {
         for (my $x = 0; $x < $CHNK_SIZE; $x++) {
            my ($cur, $top, $bot, $left, $right, $front, $back)
               = Games::Blockminer3D::Client::MapChunk::_neighbours ($map, $x, $y, $z);
            next unless $cur->[2];
            if ($cur->[0] != 0) {
               my @faces;
               my ($txtid, $surf, $uv, $model) = $RES->obj2texture ($cur->[0]);

               if ($model) {
                  unless ($model_cache{$cur->[0]}) {
                     $model_cache{$cur->[0]} = _render_model (@$model);
                  }
                  my ($verts, $txtcoords) = @{$model_cache{$cur->[0]}};

                  my $color = $cur->[1] / 15;
                  for (@$verts) {
                     push @vertexes, (
                        $_->[0] + $x, $_->[1] + $y, $_->[2] + $z
                     );
                     push @colors, (
                        $color, $color, $color,
                     );
                  }
                  $quad_cnt += scalar (@$verts) / 4;
                  push @texcoords, @$txtcoords;
                  next;
               }

               push @faces, [0, $front->[1] / 15] if $front->[4];
               push @faces, [1, $top->[1] / 15]   if $top->[4];
               push @faces, [2, $back->[1] / 15]  if $back->[4];
               push @faces, [3, $left->[1] / 15]  if $left->[4];
               push @faces, [4, $right->[1] / 15] if $right->[4];
               push @faces, [5, $bot->[1] / 15]   if $bot->[4];

               for (@faces) {
                  my ($faceidx, $color) = @$_;
                  $quad_cnt++;
                  push @vertexes, map {
                     my $v = $vertices[$indices[$faceidx * 4 + $_]];
                     (
                        $v->[0] + $x,
                        $v->[1] + $y,
                        $v->[2] + $z,
                     )
                  } 0..3;
                  push @colors, (
                     $color, $color, $color,
                     $color, $color, $color,
                     $color, $color, $color,
                     $color, $color, $color,
                  );
                  push @texcoords, (
                     $uv->[2], $uv->[3],
                     $uv->[2], $uv->[1],
                     $uv->[0], $uv->[1],
                     $uv->[0], $uv->[3],
                  );
               }
            }
         }
      }
   }
   warn "GOT: " . scalar (@vertexes) . " verts, " . scalar (@colors) . " colors and " . scalar (@texcoords) . " texcoords and $quad_cnt quads\n";
 #d#  warn "LIST[@vertexes | @colors | @texcoords]\n";

   [
      OpenGL::Array->new_list (GL_FLOAT, @vertexes),
      OpenGL::Array->new_list (GL_FLOAT, @colors),
      OpenGL::Array->new_list (GL_FLOAT, @texcoords),
      $quad_cnt
   ]

*/

void b3d_render_init ()
{
}

void
b3d_render_add_face (unsigned int face, unsigned int type, double light,
                     double xoffs, double yoffs, double zoffs,
                     double scale,
                     double xsoffs, double ysoffs, double zsoffs,
                     AV *vertex, AV *color, AV *tex)
{
 // printf ("RENDER FACE %d: %g %g %g %g\n", cur->type, xoffs, yoffs, zoffs);
  int h, j, k;
  for (h = 0; h < 4; h++)
    {
      double *vert = &(quad_vert[quad_vert_idx[face][h]][0]);
      av_push (vertex, newSVnv (((vert[0] + xoffs) * scale) + xsoffs));
      av_push (vertex, newSVnv (((vert[1] + yoffs) * scale) + ysoffs));
      av_push (vertex, newSVnv (((vert[2] + zoffs) * scale) + zsoffs));
    }

  for (h = 0; h < 12; h++) // FIXME: is this really 12??? or just 4 (for each vertex)
    av_push (color, newSVnv (light));

  b3d_obj_attr *oa = b3d_world_get_attr (type);
  double *uv = &(oa->uv[0]);

  av_push (tex, newSVnv (uv[2]));
  av_push (tex, newSVnv (uv[3]));

  av_push (tex, newSVnv (uv[2]));
  av_push (tex, newSVnv (uv[1]));

  av_push (tex, newSVnv (uv[0]));
  av_push (tex, newSVnv (uv[1]));

  av_push (tex, newSVnv (uv[0]));
  av_push (tex, newSVnv (uv[3]));
}

void
b3d_render_model (unsigned int type, double light, unsigned int xo, unsigned int yo, unsigned int zo, AV *vertex, AV *color, AV *tex)
{
  b3d_obj_attr *oa = b3d_world_get_attr (type);
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
          b3d_obj_attr *oa = b3d_world_get_attr (blktype);

          if (oa->transparent)
            continue;
          //d//printf ("MODEL FACE %d %d %d: %d %g\n", x + xo, y + yo, z + zo, blktype, scale);

          int face;
          for (face = 0; face < 6; face++)
            b3d_render_add_face (
              face, blktype, light,
              x, y, z, scale,
              xo, yo, zo,
              vertex, color, tex);
          blk_offs++;
        }
}

double b3d_cell_light (b3d_cell *c)
{
  double light = (double) c->light / 15;
  if (light < 0.1)
    light = 0.1;
  return light;
}

void
b3d_render_chunk (int x, int y, int z, AV *vertex, AV *color, AV *tex)
{
  b3d_chunk *c = b3d_world_chunk (x, y, z, 0);
  if (!c)
    return;

  LOAD_NEIGHBOUR_CHUNKS(x,y,z);

  //d// b3d_world_chunk_calc_visibility (c);

  int ix, iy, iz;
  for (iz = 0; iz < CHUNK_SIZE; iz++)
    for (iy = 0; iy < CHUNK_SIZE; iy++)
      for (ix = 0; ix < CHUNK_SIZE; ix++)
        {
//         printf ("OFFS %d %d %d \n", ix, iy, iz);
          b3d_cell *cur = b3d_world_chunk_neighbour_cell (c, ix, iy, iz, 0);
          if (!cur->visible)// || b3d_world_cell_transparent (cur))
            continue;

          b3d_obj_attr *oa = b3d_world_get_attr (cur->type);
          if (oa->model)
            {


              b3d_render_model (
                cur->type, b3d_cell_light (cur), ix, iy, iz,
                vertex, color, tex);
              continue;
            }

          GET_NEIGHBOURS(c, ix, iy, iz);

          if (b3d_world_cell_transparent (front))
            b3d_render_add_face (
              0, cur->type, b3d_cell_light (front), ix, iy, iz, 1, 0, 0, 0, vertex, color, tex);

          if (b3d_world_cell_transparent (top))
            b3d_render_add_face (
              1, cur->type, b3d_cell_light (top), ix, iy, iz, 1, 0, 0, 0, vertex, color, tex);

          if (b3d_world_cell_transparent (back))
            b3d_render_add_face (
              2, cur->type, b3d_cell_light (back), ix, iy, iz, 1, 0, 0, 0, vertex, color, tex);

          if (b3d_world_cell_transparent (left))
            b3d_render_add_face (
              3, cur->type, b3d_cell_light (left), ix, iy, iz, 1, 0, 0, 0, vertex, color, tex);

          if (b3d_world_cell_transparent (right))
            b3d_render_add_face (
              4, cur->type, b3d_cell_light (right), ix, iy, iz, 1, 0, 0, 0, vertex, color, tex);

          if (b3d_world_cell_transparent (bot))
            b3d_render_add_face (
              5, cur->type, b3d_cell_light (bot), ix, iy, iz, 1, 0, 0, 0, vertex, color, tex);
        }

  return;
}
