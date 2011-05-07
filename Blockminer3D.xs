#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>
#include <math.h>

#include "vectorlib.c"

MODULE = Games::Blockminer3D PACKAGE = Games::Blockminer3D::Math PREFIX = games_b3d_

unsigned int games_b3d_cone_sphere_intersect ( double cam_x, double cam_y, double cam_z, double cam_v_x, double cam_v_y, double cam_v_z, double cam_fov, double sphere_x, double sphere_y, double sphere_z, double sphere_rad)
  CODE:
      vec3d *cam    = vec3d_new (cam_x, cam_y, cam_z);
      vec3d *cam_v  = vec3d_new (cam_v_x, cam_v_y, cam_v_z);
      vec3d *sphere = vec3d_new (sphere_x, sphere_y, sphere_z);

      vec3d *u  = vec3d_clone (cam);
      vec3d *uv = vec3d_clone (cam_v);
      vec3d_dump ("cam", cam);
      vec3d_dump ("cam_v", cam_v);
      vec3d_dump ("sphere", sphere);
      printf ("PSPHERE %g\n", sphere_rad);
      vec3d_s_mul (uv, sphere_rad / sinl (cam_fov));
      vec3d_sub (u, uv);

      vec3d *d  = vec3d_clone (sphere);
      vec3d_sub (d, u);
      double l = vec3d_length (d);

      if (vec3d_dot (cam_v, d) >= l * cosl (cam_fov))
        {
           vec3d_assign_v (d, sphere);
           vec3d_sub (d, cam);
           l = vec3d_length (d);

           if (-vec3d_dot (cam_v, d) >= l * sinl (cam_fov))
             RETVAL = (l <= sphere_rad);
           else
             RETVAL = 1;
        }
      else
        {
          RETVAL = 0;
        }

      vec3d_free (cam);
      vec3d_free (cam_v);
      vec3d_free (sphere);
      vec3d_free (u);
      vec3d_free (uv);
      vec3d_free (d);
  OUTPUT:
    RETVAL
