#ifndef VECTORLIB_C
#define VECTORLIB_C 1
#include <stdio.h>
#include <math.h>

#define vec3_init(vname,a,b,c) double vname[3]; vname[0] = a; vname[1] = b; vname[2] = c;
#define vec3_clone(vname,vd)   vec3_init(vname,vd[0],vd[1],vd[2])
#define vec3_assign(v1,v2)     v1[0] = v2[0]; v1[1] = v2[1]; v1[2] = v2[2];
#define vec3_add(v1,v2)        v1[0] += v2[0]; v1[1] += v2[1]; v1[2] += v2[2];
#define vec3_sub(v1,v2)        v1[0] -= v2[0]; v1[1] -= v2[1]; v1[2] -= v2[2];
#define vec3_s_div(v1,s)       v1[0] /= (double) s; v1[1] /= (double) s; v1[2] /= (double) s;
#define vec3_s_mul(v1,s)       v1[0] *= (double) s; v1[1] *= (double) s; v1[2] *= (double) s;
#define vec3_dot(v1,v2)        (v1[0] * v2[0] + v1[1] * v2[1] + v1[2] * v2[2])
#define vec3_len(v)            sqrt (vec3_dot (v, v))
#define vec3_norm(v)           vec3_s_div (v, vec3_len (v))
#define vec3_floor(v)          v[0] = floor (v[0]); v[1] = floor (v[1]); v[2] = floor (v[2]);

typedef struct vec3d_ { double v[3]; } vec3d;

vec3d *vec3d_new (double a, double b, double c)
{
  vec3d *v = malloc (sizeof (vec3d));
  v->v[0] = a;
  v->v[1] = b;
  v->v[2] = c;
  return v;
}

void vec3d_free (vec3d *v)
{
  free (v);
}

vec3d *vec3d_clone (vec3d *v)
{
  return vec3d_new (v->v[0], v->v[1], v->v[2]);
}

void vec3d_assign (vec3d *v, double a, double b, double c)
{
  v->v[0] = a;
  v->v[1] = b;
  v->v[2] = c;
}

void vec3d_assign_v (vec3d *a, vec3d *b)
{ unsigned int i; for (i = 0; i < 3; i++) a->v[i] = b->v[i]; }

void vec3d_add (vec3d *a, vec3d *b)
{ unsigned int i; for (i = 0; i < 3; i++) a->v[i] += b->v[i]; }

void vec3d_addd (vec3d *a, double x, double y, double z)
{
  a->v[0] += x;
  a->v[1] += y;
  a->v[2] += z;
}

void vec3d_sub (vec3d *a, vec3d *b)
{ unsigned int i; for (i = 0; i < 3; i++) a->v[i] -= b->v[i]; }

void vec3d_subd (vec3d *a, double x, double y, double z)
{
  a->v[0] -= x;
  a->v[1] -= y;
  a->v[2] -= z;
}

void vec3d_s_add (vec3d *a, double s)
{ unsigned int i; for (i = 0; i < 3; i++) a->v[i] += s; }

void vec3d_s_sub (vec3d *a, double s)
{ unsigned int i; for (i = 0; i < 3; i++) a->v[i] -= s; }

void vec3d_s_div (vec3d *a, double s)
{ unsigned int i; for (i = 0; i < 3; i++) a->v[i] /= s; }

void vec3d_s_mul (vec3d *a, double s)
{ unsigned int i; for (i = 0; i < 3; i++) a->v[i] *= s; }

void vec3d_floor (vec3d *a)
{ unsigned int i; for (i = 0; i < 3; i++) a->v[i] = floorl (a->v[i]); }

double vec3d_dot (vec3d *a, vec3d *b)
{
  return
    a->v[0] * b->v[0]
    + a->v[1] * b->v[1]
    + a->v[2] * b->v[2];
}

vec3d *vec3d_cross_n (vec3d *a, vec3d *b)
{
  // $_[0][1] * $_[1][2] - $_[0][2] * $_[1][1],
  // $_[0][2] * $_[1][0] - $_[0][0] * $_[1][2],
  // $_[0][0] * $_[1][1] - $_[0][1] * $_[1][0],
  return vec3d_new (
    a->v[1] * b->v[2] - a->v[2] * b->v[1],
    a->v[2] * b->v[0] - a->v[0] * b->v[2],
    a->v[0] * b->v[1] - a->v[1] * b->v[0]
  );
}

double vec3d_length (vec3d *v)
{ return sqrtl (vec3d_dot (v, v)); }

void vec3d_norm (vec3d *v)
{ vec3d_s_div (v, vec3d_length (v)); }

void vec3d_dump (const char *name, vec3d *v)
{ printf ("%s [%5.4g %5.4g %5.4g] ", name, v->v[0], v->v[1], v->v[2]); }
#endif
