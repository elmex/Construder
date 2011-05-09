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


AV *
b3d_point_aabb_distance (double pt_x, double pt_y, double pt_z, double box_min_x, double box_min_y, double box_min_z, double box_max_x, double box_max_y, double box_max_z)
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

MODULE = Games::Blockminer3D PACKAGE = Games::Blockminer3D::World PREFIX = b3d_world_

void b3d_world_init ();

void b3d_world_set_chunk_data (int x, int y, int z, unsigned char *data, unsigned int len)
  CODE:
    b3d_chunk *chnk = b3d_world_chunk (x, y, z, 1);
    assert (chnk);
    b3d_world_set_chunk_from_data (chnk, data, len);
    int lenc = (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE) * 4;
    if (lenc != len)
      {
        printf ("CHUNK DATA LEN DOES NOT FIT! %d vs %d\n", len, lenc);
        exit (1);
      }

    b3d_world_chunk_calc_visibility (chnk);

    //d// b3d_world_dump ();

    /*
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
    */

int b3d_world_is_solid_at (double x, double y, double z)
  CODE:
    RETVAL = 0;

    b3d_chunk *chnk = b3d_world_chunk_at (x, y, z, 0);
    if (chnk)
      {
        b3d_cell *c = b3d_chunk_cell_at_abs (chnk, x, y, z);
        b3d_obj_attr *attr = b3d_world_get_attr (c->type);
        RETVAL = attr ? attr->blocking : 0;
      }
  OUTPUT:
    RETVAL

void b3d_world_set_object_type (unsigned int type, unsigned int transparent, unsigned int blocking);


AV *
b3d_world_at (double x, double y, double z)
  CODE:
    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    b3d_chunk *chnk = b3d_world_chunk_at (x, y, z, 0);
    if (chnk)
      {
        b3d_cell *c = b3d_chunk_cell_at_abs (chnk, x, y, z);
        av_push (RETVAL, newSViv (c->type));
        av_push (RETVAL, newSViv (c->light));
        av_push (RETVAL, newSViv (c->meta));
        av_push (RETVAL, newSViv (c->add));
        av_push (RETVAL, newSViv (c->visible));
      }

  OUTPUT:
    RETVAL


AV *
b3d_world_chunk_visible_faces (int x, int y, int z)
  CODE:
    b3d_chunk *chnk = b3d_world_chunk (x, y, z, 0);

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

void
b3d_world_test_binsearch ()
  CODE:
    b3d_axis_array arr;
    arr.alloc = 0;

    printf ("TESTING...\n");
    b3d_axis_array_insert_at (&arr, 0,  10, (void *) 10);
    b3d_axis_array_insert_at (&arr, 1, 100, (void *) 100);
    b3d_axis_array_insert_at (&arr, 2, 320, (void *) 320);
    b3d_axis_array_insert_at (&arr, 1,  11, (void *) 11);
    b3d_axis_array_insert_at (&arr, 0,  9, (void *) 9);
    b3d_axis_array_insert_at (&arr, 5,  900, (void *) 900);
    b3d_axis_array_dump (&arr);

    printf ("SERACHING...\n");
    b3d_axis_node *an = 0;
    int idx = b3d_axis_array_find (&arr, 12, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = b3d_axis_array_find (&arr, 13, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = b3d_axis_array_find (&arr, 1003, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = b3d_axis_array_find (&arr, 11, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = b3d_axis_array_find (&arr, 3, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = b3d_axis_array_find (&arr, 0, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = b3d_axis_array_find (&arr, 320, &an);
    printf ("IDX %d %p\n",idx, an);

    void *ptr = b3d_axis_array_remove_at (&arr, 2);
    printf ("removed %p\n", ptr),
    b3d_axis_array_dump (&arr);
    ptr = b3d_axis_array_remove_at (&arr, 0);
    printf ("removed %p\n", ptr),
    b3d_axis_array_dump (&arr);
    ptr = b3d_axis_array_remove_at (&arr, 3);
    printf ("removed %p\n", ptr),
    b3d_axis_array_dump (&arr);

    b3d_axis_remove (&arr, 100);
    b3d_axis_remove (&arr, 320);
    b3d_axis_remove (&arr, 10);
    b3d_axis_array_dump (&arr);
    b3d_axis_add (&arr, 9, (void *) 9);
    b3d_axis_add (&arr, 320, (void *) 320);
    idx = b3d_axis_array_find (&arr, 11, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = b3d_axis_array_find (&arr, 0, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = b3d_axis_array_find (&arr, 400, &an);
    printf ("IDX %d %p\n",idx, an);
    b3d_axis_add (&arr, 11, (void *) 11);
    b3d_axis_add (&arr, 10, (void *) 10);
    b3d_axis_add (&arr, 0, (void *) 0);
    b3d_axis_add (&arr, 50, (void *) 50);
    b3d_axis_array_dump (&arr);
    b3d_axis_remove (&arr, 12);
    b3d_axis_remove (&arr, 50);
    b3d_axis_remove (&arr, 0);
    b3d_axis_remove (&arr, 320);
    b3d_axis_array_dump (&arr);

    b3d_world_init ();
    printf ("WORLD TEST\n\n");

    printf ("*********** ADD 0, 0, 0\n");
    b3d_chunk *chnk = b3d_world_chunk (0, 0, 0, 1);
    assert (chnk);
    b3d_world_dump ();
    printf ("*********** ADD 0, 0, 1\n");
    chnk = b3d_world_chunk (0, 0, 1, 1);
    assert (chnk);
    b3d_world_dump ();
    printf ("*********** ADD 2, 3, 1\n");
    chnk = b3d_world_chunk (2, 3, 1, 1);
    assert (chnk);
    b3d_world_dump ();
