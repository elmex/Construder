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
                     AV *vertex, AV *color, AV *tex)
{
 // printf ("RENDER FACE %d: %g %g %g %g\n", cur->type, xoffs, yoffs, zoffs);
  int h, j, k;
  for (h = 0; h < 4; h++)
    {
      double *vert = &(quad_vert[quad_vert_idx[face][h]][0]);
      av_push (vertex, newSVnv (vert[0] + xoffs));
      av_push (vertex, newSVnv (vert[1] + yoffs));
      av_push (vertex, newSVnv (vert[2] + zoffs));
    }

  for (h = 0; h < 12; h++)
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
          if (!cur->visible || b3d_world_cell_transparent (cur))
            continue;

          GET_NEIGHBOURS(c, ix, iy, iz);

          if (b3d_world_cell_transparent (front))
            b3d_render_add_face (
              0, cur->type, (double) front->light / 15, ix, iy, iz, vertex, color, tex);

          if (b3d_world_cell_transparent (top))
            b3d_render_add_face (
              1, cur->type, (double) top->light / 15, ix, iy, iz, vertex, color, tex);

          if (b3d_world_cell_transparent (back))
            b3d_render_add_face (
              2, cur->type, (double) back->light / 15, ix, iy, iz, vertex, color, tex);

          if (b3d_world_cell_transparent (left))
            b3d_render_add_face (
              3, cur->type, (double) left->light / 15, ix, iy, iz, vertex, color, tex);

          if (b3d_world_cell_transparent (right))
            b3d_render_add_face (
              4, cur->type, (double) right->light / 15, ix, iy, iz, vertex, color, tex);

          if (b3d_world_cell_transparent (bot))
            b3d_render_add_face (
              5, cur->type, (double) bot->light / 15, ix, iy, iz, vertex, color, tex);
        }

  return;
}
