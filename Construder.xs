#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>
#include <math.h>

#include "counters.c"
#include "vectorlib.c"
#include "world.c"
#include "world_drawing.c"
#include "render.c"
#include "volume_draw.c"
#include "light.c"


unsigned char *ctr_chunk_read_data[CHUNK_ALEN * 4];

double region_get_sector_value (void *reg, int x, int y, int z)
{
  if (!reg)
     return 0;

  vec3_init (secpos, x, y, z);
  double l = fabs (vec3_len (secpos));
  if (l < 1)
    return 1.85; // the core
  else if (l < 200
           && ((abs (x) < 1 && abs (y) < 1)
               || (abs (z) < 1 && abs (y) < 1)
               || (abs (x) < 1 && abs (z) < 1)))
    return 1.65; // the axis, going from center to the outer construct connection
  else if (l < 30 // here we check the void: void is in the inner shell surface
           || (l > 130 // and beyond the outer shell surface, but only if inside the
                       // huge construct cube which spans 200 in each direction
               && (abs (x) < 200 && abs (y) < 200 && abs (z) < 200)))
    return 1.55; // the void
  else // we are in the sphere shell around that
    {
      double *region = reg;
      int reg_size = region[0];
      region++;

      if (x < 0) x = -x;
      if (y < 0) y = -y;
      if (z < 0) z = -z;
      x %= reg_size;
      y %= reg_size;
      z %= reg_size;

      return region[x + y * reg_size + z * reg_size * reg_size];
    }
}

unsigned int ctr_cone_sphere_intersect (double cam_x, double cam_y, double cam_z, double cam_v_x, double cam_v_y, double cam_v_z, double cam_fov, double sphere_x, double sphere_y, double sphere_z, double sphere_rad)
{
  vec3_init(cam,    cam_x, cam_y, cam_z);
  vec3_init(cam_v,  cam_v_x, cam_v_y, cam_v_z);
  vec3_init(sphere, sphere_x, sphere_y, sphere_z);
  vec3_clone(u,  cam);
  vec3_clone(uv, cam_v);
  vec3_clone(d,  sphere);

  vec3_s_mul (uv, sphere_rad / sinl (cam_fov));
  vec3_sub (u, uv);
  vec3_sub (d, u);

  double l = vec3_len (d);

  if (vec3_dot (cam_v, d) >= l * cosl (cam_fov))
    {
       vec3_assign (d, sphere);
       vec3_sub (d, cam);
       l = vec3_len (d);

       if (-vec3_dot (cam_v, d) >= l * sinl (cam_fov))
         return (l <= sphere_rad);
       else
         return 1;
    }
  else
    return 0;
}

MODULE = Games::Construder PACKAGE = Games::Construder::Math PREFIX = ctr_

unsigned int ctr_cone_sphere_intersect (double cam_x, double cam_y, double cam_z, double cam_v_x, double cam_v_y, double cam_v_z, double cam_fov, double sphere_x, double sphere_y, double sphere_z, double sphere_rad);

AV *
ctr_point_aabb_distance (double pt_x, double pt_y, double pt_z, double box_min_x, double box_min_y, double box_min_z, double box_max_x, double box_max_y, double box_max_z)
  CODE:
    vec3_init (pt,   pt_x, pt_y, pt_z);
    vec3_init (bmin, box_min_x, box_min_y, box_min_z);
    vec3_init (bmax, box_max_x, box_max_y, box_max_z);
    unsigned int i;

    double out[3];
    for (i = 0; i < 3; i++)
      {
        out[i] = pt[i];

        if (bmin[i] > bmax[i])
          {
            double swp = bmin[i];
            bmin[i] = bmax[i];
            bmax[i] = swp;
          }

        if (out[i] < bmin[i])
          out[i] = bmin[i];
        if (out[i] > bmax[i])
          out[i] = bmax[i];
      }

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    for (i = 0; i < 3; i++)
      av_push (RETVAL, newSVnv (out[i]));

  OUTPUT:
    RETVAL



AV *
ctr_calc_visible_chunks_at_in_cone (double pt_x, double pt_y, double pt_z, double rad, double cam_x, double cam_y, double cam_z, double cam_v_x, double cam_v_y, double cam_v_z, double cam_fov, double sphere_rad)
  CODE:
    int r = rad;

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    vec3_init (pt, pt_x, pt_y, pt_z);
    vec3_s_div (pt, CHUNK_SIZE);
    vec3_floor (pt);

    int x, y, z;
    for (x = -r; x <= r; x++)
      for (y = -r; y <= r; y++)
        for (z = -r; z <= r; z++)
          {
            vec3_init (chnk,  x, y, z);
            vec3_add (chnk, pt);
            vec3_clone (chnk_p, chnk);

            vec3_sub (chnk, pt);
            if (vec3_len (chnk) < rad)
              {
                vec3_clone (sphere_pos, chnk_p);
                vec3_s_mul (sphere_pos, CHUNK_SIZE);
                sphere_pos[0] += CHUNK_SIZE / 2;
                sphere_pos[1] += CHUNK_SIZE / 2;
                sphere_pos[2] += CHUNK_SIZE / 2;

                if (ctr_cone_sphere_intersect (
                      cam_x, cam_y, cam_z, cam_v_x, cam_v_y, cam_v_z,
                      cam_fov, sphere_pos[0], sphere_pos[1], sphere_pos[2],
                      sphere_rad))
                  {
                    int i;
                    for (i = 0; i < 3; i++)
                      av_push (RETVAL, newSVnv (chnk_p[i]));
                  }
              }
          }

  OUTPUT:
    RETVAL

AV *
ctr_calc_visible_chunks_at (double pt_x, double pt_y, double pt_z, double rad)
  CODE:
    int r = rad;

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    vec3_init (pt, pt_x, pt_y, pt_z);
    vec3_s_div (pt, CHUNK_SIZE);
    vec3_floor (pt);

    int x, y, z;
    for (x = -r; x <= r; x++)
      for (y = -r; y <= r; y++)
        for (z = -r; z <= r; z++)
          {
            vec3_init (chnk,  x, y, z);
            vec3_add (chnk, pt);
            vec3_clone (chnk_p, chnk);
            vec3_sub (chnk, pt);
            if (vec3_len (chnk) < rad)
              {
                int i;
                for (i = 0; i < 3; i++)
                  av_push (RETVAL, newSVnv (chnk_p[i]));
              }
          }

  OUTPUT:
    RETVAL

MODULE = Games::Construder PACKAGE = Games::Construder::Renderer PREFIX = ctr_render_

void *ctr_render_new_geom ();

void ctr_render_clear_geom (void *c);

void ctr_render_draw_geom (void *c);

void ctr_render_free_geom (void *c);

int ctr_render_chunk (int x, int y, int z, void *geom)
  CODE:
    ctr_render_clear_geom (geom);
    RETVAL = ctr_render_chunk (x, y, z, geom);
  OUTPUT:
    RETVAL

void
ctr_render_model (unsigned int type, unsigned short color, double light, unsigned int xo, unsigned int yo, unsigned int zo, void *geom, int skip, int force_model)
  CODE:
     ctr_render_clear_geom (geom);
     ctr_render_model (type, color, light, xo, yo, zo, geom, skip, force_model, 1);
     ctr_render_compile_geom (geom);

void ctr_render_init ();

void ctr_render_set_ambient_light (double l)
  CODE:
     ctr_ambient_light = l;

MODULE = Games::Construder PACKAGE = Games::Construder::World PREFIX = ctr_world_

AV *
ctr_world_get_prof_counters ()
  CODE:
    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    av_push (RETVAL, newSViv (ctr_prof_cnt.chunk_changes));
    av_push (RETVAL, newSViv (ctr_prof_cnt.active_cell_changes));
    av_push (RETVAL, newSViv (ctr_prof_cnt.allocated_axises));
    av_push (RETVAL, newSViv (ctr_prof_cnt.allocated_axises_size));
    av_push (RETVAL, newSViv (ctr_prof_cnt.noise_cnt));
    av_push (RETVAL, newSViv (ctr_prof_cnt.noise_size));
    av_push (RETVAL, newSViv (ctr_prof_cnt.dyn_buf_cnt));
    av_push (RETVAL, newSViv (ctr_prof_cnt.dyn_buf_size));
    av_push (RETVAL, newSViv (ctr_prof_cnt.geom_cnt));
    av_push (RETVAL, newSViv (ctr_prof_cnt.allocated_chunks));

  OUTPUT:
    RETVAL


void ctr_world_init (SV *change_cb, SV *cell_change_cb)
  CODE:
     ctr_world_init ();
     ctr_prof_init ();
     SvREFCNT_inc (change_cb);
     WORLD.chunk_change_cb = change_cb;
     SvREFCNT_inc (cell_change_cb);
     WORLD.active_cell_change_cb = cell_change_cb;


int
ctr_world_has_chunk (int x, int y, int z)
  CODE:
    ctr_chunk *chnk = ctr_world_chunk (x, y, z, 0);
    RETVAL = chnk ? 1 : 0;
  OUTPUT:
    RETVAL

SV *
ctr_world_get_chunk_data (int x, int y, int z)
  CODE:
    ctr_chunk *chnk = ctr_world_chunk (x, y, z, 0);
    if (!chnk)
      {
        XSRETURN_UNDEF;
      }

    int len = CHUNK_ALEN * 4;
    ctr_world_get_chunk_data (chnk, (unsigned char *) &ctr_chunk_read_data);
    RETVAL = newSVpv ((unsigned char *) &ctr_chunk_read_data, len);
  OUTPUT:
    RETVAL


int ctr_world_set_chunk_data (int x, int y, int z, unsigned char *data, unsigned int len)
  CODE:
    ctr_chunk *chnk = ctr_world_chunk (x, y, z, 1);
    assert (chnk);
    RETVAL = ctr_world_set_chunk_from_data (chnk, data, len);
    int lenc = (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE) * 4;
    if (lenc != len)
      {
        printf ("CHUNK DATA LEN DOES NOT FIT! %d vs %d\n", len, lenc);
        exit (1);
      }

    // FIXME: this needs to be done for neighborss where whe changed too!!!
    ctr_world_chunk_calc_visibility (chnk);

    ctr_world_emit_chunk_change (x, y, z);

    //d// ctr_world_dump ();
  OUTPUT:
    RETVAL

void ctr_world_purge_chunk (int x, int y, int z);

int ctr_world_is_solid_at (double x, double y, double z)
  CODE:
    RETVAL = 1;

    ctr_chunk *chnk = ctr_world_chunk_at (x, y, z, 0);
    if (chnk)
      {
        ctr_cell *c = ctr_chunk_cell_at_abs (chnk, x, y, z);
        ctr_obj_attr *attr = ctr_world_get_attr (c->type);
        RETVAL = attr ? attr->blocking : 0;
      }
  OUTPUT:
    RETVAL

void ctr_world_set_object_type (unsigned int type, unsigned int transparent, unsigned int blocking, unsigned int has_txt, unsigned int active, double uv0, double uv1, double uv2, double uv3);

void ctr_world_set_object_model (unsigned int type, unsigned int dim, AV *blocks);

AV *
ctr_world_at (double x, double y, double z)
  CODE:
    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    ctr_chunk *chnk = ctr_world_chunk_at (x, y, z, 0);
    if (chnk)
      {
        ctr_cell *c = ctr_chunk_cell_at_abs (chnk, x, y, z);
        av_push (RETVAL, newSViv (c->type));
        av_push (RETVAL, newSViv (c->light));
        av_push (RETVAL, newSViv (c->meta));
        av_push (RETVAL, newSViv (c->add));
        av_push (RETVAL, newSViv (c->visible));
      }

  OUTPUT:
    RETVAL

AV *
ctr_world_chunk_visible_faces (int x, int y, int z)
  CODE:
    ctr_chunk *chnk = ctr_world_chunk (x, y, z, 0);

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    for (z = 0; z < CHUNK_SIZE; z++)
      for (y = 0; y < CHUNK_SIZE; y++)
        for (x = 0; x < CHUNK_SIZE; x++)
          {
            if (chnk->cells[REL_POS2OFFS(x, y, z)].visible)
              {
                av_push (RETVAL, newSViv (chnk->cells[REL_POS2OFFS(x, y, z)].type));
                av_push (RETVAL, newSVnv (x));
                av_push (RETVAL, newSVnv (y));
                av_push (RETVAL, newSVnv (z));
              }
          }

  OUTPUT:
    RETVAL

void ctr_world_query_load_chunks (int alloc = 0);

void ctr_world_query_set_at (unsigned int rel_x, unsigned int rel_y, unsigned int rel_z, AV *cell)
  CODE:
    ctr_world_query_set_at_pl (rel_x, rel_y, rel_z, cell);

void ctr_world_query_set_at_abs (unsigned int rel_x, unsigned int rel_y, unsigned int rel_z, AV *cell)
  CODE:
    ctr_world_query_abs2rel (&rel_x, &rel_y, &rel_z);
    ctr_world_query_set_at_pl (rel_x, rel_y, rel_z, cell);

void ctr_world_query_setup (int x, int y, int z, int ex, int ey, int ez);

int ctr_world_query_desetup (int no_update = 0);

AV *ctr_world_query_possible_light_positions ()
  CODE:
    int xw = QUERY_CONTEXT.x_w * CHUNK_SIZE,
        yw = QUERY_CONTEXT.y_w * CHUNK_SIZE,
        zw = QUERY_CONTEXT.z_w * CHUNK_SIZE;

    static int offsets[6][3] = {
        {  0,  0,  1 },
        {  0,  0, -1 },
        {  0,  1,  0 },
        {  0, -1,  0 },
        {  1,  0,  0 },
        { -1,  0,  0 },
    };

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    int x, y, z;
    for (x = 2; x < (xw - 2); x += 6)
      for (y = 2; y < (yw - 2); y += 6)
        for (z = 2; z < (zw - 2); z += 6)
           {
             int ix, iy, iz;
             int rad, found = 0;
             int i;
             int fnd = 0;
             for (i = 0; !fnd && i < 6; i++)
               {
                 int m;
                 for (m = 1; m <= 2; m++)
                   {
                     int px = x + offsets[i][0] * (m - 1),
                         py = y + offsets[i][1] * (m - 1),
                         pz = z + offsets[i][2] * (m - 1);

                     ctr_cell *cur = ctr_world_query_cell_at (px, py, pz, 0);
                     if (!cur || cur->type != 0)
                       continue;

                     cur = ctr_world_query_cell_at (
                       x + offsets[i][0] * m,
                       y + offsets[i][1] * m,
                       z + offsets[i][2] * m,
                       0);
                     if (cur && cur->type != 0)
                       {
                         av_push (RETVAL,
                                  newSViv (px + QUERY_CONTEXT.chnk_x * CHUNK_SIZE));
                         av_push (RETVAL,
                                  newSViv (py + QUERY_CONTEXT.chnk_y * CHUNK_SIZE));
                         av_push (RETVAL,
                                  newSViv (pz + QUERY_CONTEXT.chnk_z * CHUNK_SIZE));
                         fnd = 1;
                         break;
                       }
                   }
               }
           }
  OUTPUT:
    RETVAL

AV *ctr_world_find_free_spot (int x, int y, int z, int with_floor)
  CODE:
    vec3_init (pos, x, y, z);
    vec3_s_div (pos, CHUNK_SIZE);
    vec3_floor (pos);
    int chnk_x = pos[0],
        chnk_y = pos[1],
        chnk_z = pos[2];

    ctr_world_query_setup (
      chnk_x - 2, chnk_y - 2, chnk_z - 2,
      chnk_x + 2, chnk_y + 2, chnk_z + 2
    );

    ctr_world_query_load_chunks (0);

    int cx = x, cy = y, cz = z;
    ctr_world_query_abs2rel (&cx, &cy, &cz);

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    int rad;
    int ix, iy, iz;
    int found = 0;
    for (rad = 0; !found && rad < ((CHUNK_SIZE * 2) - 3); rad++) // -3 safetymargin
      for (ix = -rad; !found && ix <= rad; ix++)
        for (iy = -rad; !found && iy <= rad; iy++)
          for (iz = -rad; !found && iz <= rad; iz++)
            {
              int dx = ix + cx,
                  dy = iy + cy,
                  dz = iz + cz;

              ctr_cell *cur = ctr_world_query_cell_at (dx, dy, dz, 0);
              if (!cur)
                continue;
              ctr_obj_attr *attr = ctr_world_get_attr (cur->type);
              if (attr->blocking)
                continue;

              cur = ctr_world_query_cell_at (dx, dy + 1, dz, 0);
              if (!cur)
                continue;
              attr = ctr_world_get_attr (cur->type);
              if (attr->blocking)
                continue;

              cur = ctr_world_query_cell_at (dx, dy - 1, dz, 0);
              if (!cur)
                continue;
              attr = ctr_world_get_attr (cur->type);
              if (with_floor && !attr->blocking)
                continue;

              av_push (RETVAL, newSViv (x + ix));
              av_push (RETVAL, newSViv (y + iy));
              av_push (RETVAL, newSViv (z + iz));
              found = 1;
            }

  OUTPUT:
    RETVAL

AV *ctr_world_get_types_in_cube (int x, int y, int z, int size, int type_match = -1)
  CODE:
    vec3_init (pos1, x, y, z);
    vec3_s_div (pos1, CHUNK_SIZE);
    vec3_floor (pos1);

    vec3_init (pos2, x + size, y + size, z + size);
    vec3_s_div (pos2, CHUNK_SIZE);
    vec3_floor (pos2);

    ctr_world_query_setup (
      (int) pos1[0], (int) pos1[1], (int) pos1[2],
      (int) pos2[0], (int) pos2[1], (int) pos2[2]
    );

    ctr_world_query_load_chunks (0);

    int cx = x, cy = y, cz = z;
    ctr_world_query_abs2rel (&cx, &cy, &cz);

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    int dx, dy, dz;
    for (dx = 0; dx < size; dx++)
      for (dy = 0; dy < size; dy++)
        for (dz = 0; dz < size; dz++)
          {
            ctr_cell *cur = ctr_world_query_cell_at (cx + dx, cy + dy, cz + dz, 0);
            if (!cur)
              continue;

            if (type_match >= 0)
              {
                if (cur->type == type_match)
                  {
                    av_push (RETVAL, newSViv (x + dx));
                    av_push (RETVAL, newSViv (y + dy));
                    av_push (RETVAL, newSViv (z + dz));
                    av_push (RETVAL, newSViv (cur->type));
                  }
              }
            else
              av_push (RETVAL, newSViv (cur->type));
          }

    ctr_world_query_desetup (1);

  OUTPUT:
    RETVAL

AV *ctr_world_get_pattern (int x, int y, int z, int mutate)
  CODE:
    vec3_init (pos, x, y, z);
    vec3_s_div (pos, CHUNK_SIZE);
    vec3_floor (pos);
    int chnk_x = pos[0],
        chnk_y = pos[1],
        chnk_z = pos[2];

    ctr_world_query_setup (
      chnk_x - 1, chnk_y - 1, chnk_z - 1,
      chnk_x + 1, chnk_y + 1, chnk_z + 1
    );

    ctr_world_query_load_chunks (0);

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    // calc relative size inside chunks:
    int cx = x, cy = y, cz = z;
    ctr_world_query_abs2rel (&cx, &cy, &cz);

    //d// printf ("QUERY AT %d %d %d\n", cx, cy, cz);

    // find lowest cx/cz coord with constr. floor
    ctr_cell *cur = ctr_world_query_cell_at (cx, cy, cz, 0);
    while (cur && cur->type == 36)
      {
        cx--;
        printf ("CX %d\n", cx);
        cur = ctr_world_query_cell_at (cx, cy, cz, 0);
      }

    cx++;
    cur = ctr_world_query_cell_at (cx, cy, cz, 0);
    while (cur && cur->type == 36)
      {
        cz--;
        cur = ctr_world_query_cell_at (cx, cy, cz, 0);
      }
    cz++;

    //d// printf ("MINX FOUND %d %d\n", cx, cz);

    // find out how large the floor is
    int dim;
    for (dim = 5; dim >= 1; dim--)
      {
        int no_floor = 0;

        int dx, dz;
        for (dx = 0; dx < dim; dx++)
          for (dz = 0; dz < dim; dz++)
            {
              ctr_cell *cur = ctr_world_query_cell_at (cx + dx, cy, cz + dz, 0);
              //d// printf ("TXT[%d] %d %d %d: %d\n", dim, cx + dx, cy, cz + dz, cur->type);
              if (!cur || cur->type != 36)
                no_floor = 1;
            }
        if (!no_floor)
          break;
      }

    if (dim <= 0)
      {
        ctr_world_query_desetup (1);
        XSRETURN_UNDEF;
      }

    //d// printf ("floor dimension: %d\n", dim);
    // next: search first x/z coord with a block over it
    int min_x = 100, min_y = 100, min_z = 100, max_x = 0, max_y = 0, max_z = 0;
    int dx, dy, dz;
    int fnd = 0;
    for (dy = 1; dy <= dim; dy++)
      for (dz = 0; dz < dim; dz++)
        for (dx = 0; dx < dim; dx++)
          {
            int ix = dx + cx,
                iy = dy + cy,
                iz = dz + cz;
            cur = ctr_world_query_cell_at (ix, iy, iz, 0);
            if (cur && cur->type != 0)
              {
                if (min_x > ix) min_x = ix;
                if (min_y > iy) min_y = iy;
                if (min_z > iz) min_z = iz;
              }
          }

    for (dy = 1; dy <= dim; dy++)
      for (dz = 0; dz < dim; dz++)
        for (dx = 0; dx < dim; dx++)
          {
            int ix = dx + cx,
                iy = dy + cy,
                iz = dz + cz;
            cur = ctr_world_query_cell_at (ix, iy, iz, 0);
            if (cur && cur->type != 0)
              {
                if (max_x < ix) max_x = ix;
                if (max_y < iy) max_y = iy;
                if (max_z < iz) max_z = iz;
              }
          }

    dim = 0;
    if (((max_x - min_x) + 1) > dim)
      dim = (max_x - min_x) + 1;
    if (((max_y - min_y) + 1) > dim)
      dim = (max_y - min_y) + 1;
    if (((max_z - min_z) + 1) > dim)
      dim = (max_z - min_z) + 1;

    //d// printf ("FOUND MIN MAX %d %d %d, %d %d %d, dimension: %d\n", min_x, min_y, min_z, max_x, max_y, max_z, dim);

    if (!mutate)
      av_push (RETVAL, newSViv (dim));

    int blk_nr = 1;
    for (dy = 0; dy < dim; dy++)
      for (dz = 0; dz < dim; dz++)
        for (dx = 0; dx < dim; dx++)
          {
            int ix = min_x + dx,
                iy = min_y + dy,
                iz = min_z + dz;

            // outside construction pad:
            if (ix > max_x || iy > max_y || iz > max_z)
              {
                blk_nr++; // but is just empty space of pattern
                continue;
              }

            cur = ctr_world_query_cell_at (ix, iy, iz, 0);
            if (cur && cur->type != 0)
              {
                if (mutate == 1)
                  {
                    av_push (RETVAL, newSViv ((chnk_x - 1) * CHUNK_SIZE + ix));
                    av_push (RETVAL, newSViv ((chnk_y - 1) * CHUNK_SIZE + iy));
                    av_push (RETVAL, newSViv ((chnk_z - 1) * CHUNK_SIZE + iz));
                  }
                else
                  {
                    av_push (RETVAL, newSViv (blk_nr));
                    av_push (RETVAL, newSViv (cur->type));
                  }
              }

            blk_nr++;
          }

    ctr_world_query_desetup (1);

  OUTPUT:
    RETVAL


#define DEBUG_LIGHT 0

void ctr_world_flow_light_query_setup (int minx, int miny, int minz, int maxx, int maxy, int maxz)
  CODE:
    vec3_init (min_pos, minx, miny, minz);
    vec3_s_div (min_pos, CHUNK_SIZE);
    vec3_floor (min_pos);
    vec3_init (max_pos, maxx, maxy, maxz);
    vec3_s_div (max_pos, CHUNK_SIZE);
    vec3_floor (max_pos);

    ctr_world_query_setup (
      min_pos[0] - 2, min_pos[1] - 2, min_pos[2] - 2,
      max_pos[0] + 2, max_pos[1] + 2, max_pos[2] + 2
    );

    ctr_world_query_load_chunks (0);


AV *ctr_world_query_search_types (int t1, int t2, int t3)
  CODE:
    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    int xw = QUERY_CONTEXT.x_w * CHUNK_SIZE,
        yw = QUERY_CONTEXT.y_w * CHUNK_SIZE,
        zw = QUERY_CONTEXT.z_w * CHUNK_SIZE;
    int x, y, z;
    for (x = 0; x < xw; x++)
      for (y = 0; y < yw; y++)
        for (z = 0; z < zw; z++)
           {
             ctr_cell *cur = ctr_world_query_cell_at (x, y, z, 0);
             if (cur && (cur->type == t1 || cur->type == t2 || cur->type == t3))
               {
                  int rx = x, ry = y, rz = z;
                  ctr_world_query_rel2abs (&rx, &ry, &rz);
                  av_push (RETVAL, newSViv (rx));
                  av_push (RETVAL, newSViv (ry));
                  av_push (RETVAL, newSViv (rz));
               }
           }

  OUTPUT:
    RETVAL

void ctr_world_query_reflow_every_light ()
  CODE:
    int xw = QUERY_CONTEXT.x_w * CHUNK_SIZE,
        yw = QUERY_CONTEXT.y_w * CHUNK_SIZE,
        zw = QUERY_CONTEXT.z_w * CHUNK_SIZE;
    int x, y, z;
    for (x = 0; x < xw; x++)
      for (y = 0; y < yw; y++)
        for (z = 0; z < zw; z++)
           {
             ctr_cell *cur = ctr_world_query_cell_at (x, y, z, 0);
             if (cur && (cur->type == 35 || cur->type == 40 || cur->type == 41))
               ctr_world_query_reflow_light (x, y, z);
           }

void ctr_world_flow_light_at (int x, int y, int z)
  CODE:
    ctr_world_query_abs2rel (&x, &y, &z);
    ctr_world_query_reflow_light (x, y, z);


MODULE = Games::Construder PACKAGE = Games::Construder::VolDraw PREFIX = vol_draw_

void vol_draw_init ();

void vol_draw_alloc (unsigned int size);

void vol_draw_set_op (unsigned int op);

void vol_draw_set_dst (unsigned int i);

void vol_draw_set_src (unsigned int i);

void vol_draw_set_dst_range (double a, double b);

void vol_draw_set_src_range (double a, double b);

void vol_draw_set_src_blend (double r);

void vol_draw_val (double val);

void vol_draw_dst_self ();

void vol_draw_subdiv (int type, float x, float y, float z, float size, float shrink_fact, int lvl);

void vol_draw_fill_simple_noise_octaves (unsigned int seed, unsigned int octaves, double factor, double persistence);

void vol_draw_mandel_box (double xc, double yc, double zc, double xsc, double ysc, double zsc, double s, double r, double f, int it, double cfact);

void vol_draw_menger_sponge_box (float x, float y, float z, float size, unsigned short lvl);

void vol_draw_cantor_dust_box (float x, float y, float z, float size, unsigned short lvl);

void vol_draw_sierpinski_pyramid (float x, float y, float z, float size, unsigned short lvl);

void vol_draw_self_sim_cubes_hash_seed (float x, float y, float z, float size, unsigned int corners, unsigned int seed, unsigned short lvl);

void vol_draw_map_range (float a, float b, float x, float y);

void vol_draw_copy (void *dst_arr);

void vol_draw_histogram_equalize (int buckets, double a, double b);

int vol_draw_count_in_range (double a, double b)
  CODE:
    int c = 0;
    int x, y, z;
    for (x = 0; x < DRAW_CTX.size; x++)
      for (y = 0; y < DRAW_CTX.size; y++)
        for (z = 0; z < DRAW_CTX.size; z++)
          {
            double v = DRAW_DST (x, y, z);
            if (v >= a && v < b)
              c++;
          }
    RETVAL = c;
  OUTPUT:
    RETVAL


AV *vol_draw_to_perl ()
  CODE:
    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);
    av_push (RETVAL, newSViv (DRAW_CTX.size));

    int x, y, z;
    for (x = 0; x < DRAW_CTX.size; x++)
      for (y = 0; y < DRAW_CTX.size; y++)
        for (z = 0; z < DRAW_CTX.size; z++)
          av_push (RETVAL, newSVnv (DRAW_DST (x, y, z)));

  OUTPUT:
    RETVAL

void vol_draw_dst_to_world (int sector_x, int sector_y, int sector_z, AV *range_map)
  CODE:
    int cx = sector_x * CHUNKS_P_SECTOR,
        cy = sector_y * CHUNKS_P_SECTOR,
        cz = sector_z * CHUNKS_P_SECTOR;

    ctr_world_query_setup (
      cx, cy, cz,
      cx + (CHUNKS_P_SECTOR - 1),
      cy + (CHUNKS_P_SECTOR - 1),
      cz + (CHUNKS_P_SECTOR - 1)
    );

    ctr_world_query_load_chunks (1);
    int x, y, z;
    for (x = 0; x < DRAW_CTX.size; x++)
      for (y = 0; y < DRAW_CTX.size; y++)
        for (z = 0; z < DRAW_CTX.size; z++)
          {
            ctr_cell *cur = ctr_world_query_cell_at (x, y, z, 1);
            assert (cur);
            double v = DRAW_DST(x, y, z);

            int al = av_len (range_map);
            int i;
            for (i = 0; i <= al; i += 3)
              {
                SV **a = av_fetch (range_map, i, 0);
                SV **b = av_fetch (range_map, i + 1, 0);
                SV **t = av_fetch (range_map, i + 2, 0);
                if (!a || !b || !v)
                  continue;

                double av = SvNV (*a),
                       bv = SvNV (*b);
                if (v >= av && v < bv)
                  {
                    cur->type = SvIV (*t);
                    if (ctr_world_is_active (cur->type))
                      ctr_world_emit_active_cell_change (x, y, z, cur, 0);
                  }
              }
          }

MODULE = Games::Construder PACKAGE = Games::Construder::Random PREFIX = random_

unsigned int rnd_xor (unsigned int x);

double rnd_float (unsigned int x)
  CODE:
    double val = (double) x / (double) 0xFFFFFFFF;
    RETVAL = val;
  OUTPUT:
    RETVAL

MODULE = Games::Construder PACKAGE = Games::Construder::Region PREFIX = region_

void *region_new_from_vol_draw_dst ()
  CODE:
    double *region =
       safemalloc ((sizeof (double) * DRAW_CTX.size * DRAW_CTX.size * DRAW_CTX.size) + 1);
    RETVAL = region;

    region[0] = DRAW_CTX.size;
    region++;
    vol_draw_copy (region);

  OUTPUT:
    RETVAL

unsigned int region_get_sector_seed (int x, int y, int z)
  CODE:
    RETVAL = map_coord2int (x, y, z);
  OUTPUT:
    RETVAL

AV *region_get_nearest_sector_in_range (void *reg, int x, int y, int z, double a, double b)
  CODE:
     double *region = reg;
     int reg_size = region[0];
     region++;

     RETVAL = newAV ();
     sv_2mortal ((SV *)RETVAL);

     int rad;
     for (rad = 1; rad < 200; rad++)
       {
         int fnd = 0;
         int dx, dy, dz;
         for (dx = -rad; dx <= rad; dx++)
           for (dy = -rad; dy <= rad; dy++)
             for (dz = -rad; dz <= rad; dz++)
               {
                 int ox = x + dx,
                     oy = y + dy,
                     oz = z + dz;

                 double v = region_get_sector_value (reg, ox, oy, oz);
                 if (v < a || v >= b)
                   continue;

                 av_push (RETVAL, newSViv (x + dx));
                 av_push (RETVAL, newSViv (y + dy));
                 av_push (RETVAL, newSViv (z + dz));
                 fnd = 1;
               }

         if (fnd)
           break;
       }

  OUTPUT:
    RETVAL

double region_get_sector_value (void *reg, int x, int y, int z);
