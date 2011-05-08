#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>
#include <math.h>

#include "vectorlib.c"
#include "world.c"

MODULE = Games::Blockminer3D PACKAGE = Games::Blockminer3D::Math PREFIX = b3d_

unsigned int b3d_cone_sphere_intersect ( double cam_x, double cam_y, double cam_z, double cam_v_x, double cam_v_y, double cam_v_z, double cam_fov, double sphere_x, double sphere_y, double sphere_z, double sphere_rad)
  CODE:
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
             RETVAL = (l <= sphere_rad);
           else
             RETVAL = 1;
        }
      else
        {
          RETVAL = 0;
        }

  OUTPUT:
    RETVAL

MODULE = Games::Blockminer3D PACKAGE = Games::Blockminer3D::World PREFIX = b3d_world_

void b3d_world_init ();

void b3d_world_set_chunk_data (int x, int y, int z, unsigned char *data, unsigned int len)
  CODE:
    b3d_chunk *chnk = b3d_world_chunk (x, y, z);
    b3d_world_set_chunk_from_data (chnk, data, len);
    int lenc = (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE) * 4;
    if (lenc != len)
      {
        printf ("CHUNK DATA LEN DOES NOT FIT! %d vs %d\n", len, lenc);
        exit (1);
      }

    unsigned char *datac = malloc (sizeof (unsigned char) * lenc);
    b3d_world_get_chunk_data (chnk, datac);
    int i;
    for (i = 0; i < lenc; i++)
      {
        if (data[i] != datac[i])
          {
            printf ("BUG! AT %d %x %d\n", i, data[i], datac[i]);
            exit (1);
          }
      }

int b3d_world_is_solid_at (double x, double y, double z)
  CODE:
    b3d_chunk *chnk = b3d_world_chunk_at (x, y, z);
    b3d_cell *c = b3d_chunk_cell_at_abs (chnk, x, y, z);
    RETVAL = (c->type != 0);
  OUTPUT:
    RETVAL
