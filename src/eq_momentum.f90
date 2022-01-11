module eq_momentum_mod
  use precision_mod, only : WP
  implicit none
  private :: Calculate_momentum_driven_source
  private :: Calculate_momentum_fractional_step
  private :: Compute_momentum_rhs
  private :: Correct_massflux
  public  :: Solve_momentum_eq

contains
!===============================================================================
!===============================================================================
!> \brief To calcuate the driven force for streamwise peridic flow.
!>
!> This subroutine is called everytime when calcuting the rhs of momentum eqs.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[inout]  rhs          the rhs of the momentum equation
!> \param[in]     d            domain name
!> \param[in]     isub         the RK iteration to get correct Coefficient 
!_______________________________________________________________________________
  subroutine Calculate_momentum_driven_source(rhs, d, isub)
    use input_general_mod,       only : idriven, drvf,  IDRVF_NO, IDRVF_MASSFLUX, &
                                        IDRVF_SKINFRIC, IDRVF_PRESLOSS, &
                                        tAlpha, dt
    use operations,              only : Get_volumetric_average_3d
    use udf_type_mod,            only : t_domain
    use parameters_constant_mod, only : HALF, ZERO
    implicit none

    real(WP),       intent(inout) :: rhs(:, :, :)
    integer(4),     intent(in   ) :: isub
    type(t_domain), intent(in   ) :: d

    real(WP) :: rhs_bulk
    logical :: is_stored_nyp

    rhs_bulk = ZERO

    if(idriven == IDRVF_MASSFLUX) then

      is_stored_nyp = .false.
      call Get_volumetric_average_3d(d, rhs, rhs_bulk, is_stored_nyp)
      
    else if (idriven == IDRVF_SKINFRIC) then

      rhs_bulk = - HALF * drvf * tAlpha(isub) * dt

    else if (idriven == IDRVF_PRESLOSS ) then

      ! to check this part
      rhs_bulk = - HALF * drvf * tAlpha(isub) * dt

    else 
      return
    end if

    rhs(:, :, :) = rhs(:, :, :) - rhs_bulk

    return
  end subroutine 
!===============================================================================
!===============================================================================
!> \brief To calcuate the convection and diffusion terms in rhs of momentum eq.
!>
!> This subroutine is called everytime when calcuting the rhs of momentum eqs.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[inout]  rhs0          the last iteration rhs
!> \param[inout]  rhs1          the current iteration rhs
!> \param[in]     rhs1_semi     the semi-implicit term
!> \param[in]     isub          the RK iteration to get correct Coefficient 
!_______________________________________________________________________________
  subroutine Calculate_momentum_fractional_step(rhs0, rhs1, rhs1_semi, isub)
    use input_general_mod, only : tGamma, tZeta, tAlpha, dt, &
                                  IVIS_SEMIMPLT, iviscous
    implicit none
    real(WP), dimension(:, :, :), intent(in   ) :: rhs1_semi
    real(WP), dimension(:, :, :), intent(inout) :: rhs0, rhs1
    integer(4),                   intent(in   ) :: isub

    integer(4) :: n(3)
    real(WP), allocatable :: rhs_dummy(:, :, :)

    n(1:3) = shape(rhs1)
    allocate( rhs_dummy (n(1), n(2), n(3)) )

    ! add explicit terms
    rhs_dummy(:, :, :) = rhs1(:, :, :)
    rhs1(:, :, :) = tGamma(isub) * rhs1(:, :, :) + &
                    tZeta (isub) * rhs0(:, :, :)
    rhs0(:, :, :) = rhs_dummy(:, :, :)

    ! add implicit
    rhs1(:, :, :) = rhs1(:, :, :) + &
                    tAlpha(isub) * rhs1_semi(:, :, :)
  
    ! times the time step 
    rhs1(:, :, :) = dt * rhs1(:, :, :)

    deallocate (rhs_dummy)

    return
  end subroutine
!===============================================================================
!===============================================================================
!> \brief To calcuate all rhs of momentum eq.
!>
!> This subroutine is called everytime when calcuting the rhs of momentum eqs.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[inout]  f             flow field
!> \param[inout]  d             domain    
!> \param[in]     isub          the RK iteration to get correct Coefficient 
!_______________________________________________________________________________
  subroutine Compute_momentum_rhs(f, d, isub)
    use input_general_mod,       only : ithermo, igravity, idriven, &
                                        sigma1p, &   
                                        IDRVF_NO, IVIS_EXPLICIT, IVIS_SEMIMPLT
    use udf_type_mod,            only : t_flow, t_domain
    use parameters_constant_mod, only : TWO, ZERO, ONE_THIRD, TWO_THIRD
    use operations
    implicit none

    type(t_flow),   intent(inout) :: f
    type(t_domain), intent(in   ) :: d
    integer(4),     intent(in   ) :: isub
!-------------------------------------------------------------------------------
! ithermo == 0, vars
!-------------------------------------------------------------------------------
    ! x-pencil based
    real(WP), dimension( d%nc(1), d%nc(2), d%nc(3) ) :: qxxc ! ux at (xc, yc, zc)
    real(WP), dimension( d%np(1), d%np(2), d%nc(3) ) :: qyxp ! uy at (xp, yp, zc)
    real(WP), dimension( d%np(1), d%nc(2), d%np(3) ) :: qzxp ! uz at (xp, yc, zp)
    ! y-pencil based
    real(WP), dimension( d%np(1), d%np(2), d%nc(3) ) :: qxyp ! ux at (xp, yp, zc)
    real(WP), dimension( d%nc(1), d%nc(2), d%nc(3) ) :: qyyc ! uy at (xc, yc, zc)
    real(WP), dimension( d%nc(1), d%np(2), d%np(3) ) :: qzyp ! uz at (xc, yp, zp)
    ! z-pencil based
    real(WP), dimension( d%np(1), d%nc(2), d%np(3) ) :: qxzp ! ux at (xp, yc, zp)
    real(WP), dimension( d%nc(1), d%np(2), d%np(3) ) :: qyzp ! uy at (xc, yp, zp)
    real(WP), dimension( d%nc(1), d%nc(2), d%nc(3) ) :: qzzc ! uz at (xc, yc, zc)

!-------------------------------------------------------------------------------
! ithermo == 1, vars
!-------------------------------------------------------------------------------
    ! x-pencil based
    real(WP), dimension( d%nc(1), d%nc(2), d%nc(3) ) :: gxxc ! gx at (xc, yc, zc), g_i = rho * u_i
    real(WP), dimension( d%np(1), d%np(2), d%nc(3) ) :: gyxp ! gy at (xp, yp, zc)
    real(WP), dimension( d%np(1), d%nc(2), d%np(3) ) :: gzxp ! gz at (xp, yc, zp)
    ! y-pencil based
    real(WP), dimension( d%np(1), d%np(2), d%nc(3) ) :: gxyp ! gx at (xp, yp, zc)
    real(WP), dimension( d%nc(1), d%nc(2), d%nc(3) ) :: gyyc ! gy at (xc, yc, zc)
    real(WP), dimension( d%nc(1), d%np(2), d%np(3) ) :: gzyp ! gz at (xc, yp, zp)
    ! z-pencil based
    real(WP), dimension( d%np(1), d%nc(2), d%np(3) ) :: gxzp ! gx at (xp, yc, zp)
    real(WP), dimension( d%nc(1), d%np(2), d%np(3) ) :: gyzp ! gy at (xc, yp, zp)
    real(WP), dimension( d%nc(1), d%nc(2), d%nc(3) ) :: gzzc ! gz at (xc, yc, zc)
    ! x-pencil based
    real(WP), dimension( d%np(1), d%nc(2), d%nc(3) ) :: mxp     ! mu       at (xp, yc, zc)
    real(WP), dimension( d%np(1), d%nc(2), d%nc(3) ) :: dmdx_xp ! d(mu)/dx at (xp, yc, zc)
    real(WP), dimension( d%np(1), d%nc(2), d%nc(3) ) :: dmdy_xp ! d(mu)/dy at (xp, yc, zc)
    real(WP), dimension( d%np(1), d%nc(2), d%nc(3) ) :: dmdz_xp ! d(mu)/dz at (xp, yc, zc)
    ! y-pencil based
    real(WP), dimension( d%nc(1), d%np(2), d%nc(3) ) :: myp     ! mu       at (xc, yp, zc)
    real(WP), dimension( d%nc(1), d%np(2), d%nc(3) ) :: dmdx_yp ! d(mu)/dx at (xc, yp, zc)
    real(WP), dimension( d%nc(1), d%np(2), d%nc(3) ) :: dmdy_yp ! d(mu)/dy at (xc, yp, zc)
    real(WP), dimension( d%nc(1), d%np(2), d%nc(3) ) :: dmdz_yp ! d(mu)/dz at (xc, yp, zc)
    ! z-pencil based
    real(WP), dimension( d%nc(1), d%nc(2), d%np(3) ) :: mzp     ! mu       at (xc, yc, zp)
    real(WP), dimension( d%nc(1), d%nc(2), d%np(3) ) :: dmdx_zp ! d(mu)/dx at (xc, yc, zp)
    real(WP), dimension( d%nc(1), d%nc(2), d%np(3) ) :: dmdy_zp ! d(mu)/dy at (xc, yc, zp)
    real(WP), dimension( d%nc(1), d%nc(2), d%np(3) ) :: dmdz_zp ! d(mu)/dz at (xc, yc, zp)
    
    real(WP), dimension( d%nc(1), d%nc(2), d%nc(3) ) :: div0, div ! divergence at cell centre at (xc, yc, zc)
    
!-------------------------------------------------------------------------------
! common vars
!-------------------------------------------------------------------------------
    ! natural position as in staggered storage
    real(WP), dimension( d%np(1), d%nc(2), d%nc(3) ) :: m1_rhs ! rhs for momentum-x at (xp, yc, zc)
    real(WP), dimension( d%nc(1), d%np(2), d%nc(3) ) :: m2_rhs ! rhs for momentum-y at (xc, yp, zc)
    real(WP), dimension( d%nc(1), d%nc(2), d%np(3) ) :: m3_rhs ! rhs for momentum-z at (xc, yc, zp)

    real(WP), dimension( d%np(1), d%nc(2), d%nc(3) ) :: m1_rhs_implicit ! rhs for momentum-x at (xp, yc, zc)
    real(WP), dimension( d%nc(1), d%np(2), d%nc(3) ) :: m2_rhs_implicit ! rhs for momentum-y at (xc, yp, zc)
    real(WP), dimension( d%nc(1), d%nc(2), d%np(3) ) :: m3_rhs_implicit ! rhs for momentum-z at (xc, yc, zp)

    real(WP), dimension( d%np(1), d%nc(2), d%nc(3) ) :: m1_rhs_implicit0 ! rhs for momentum-x at (xp, yc, zc)
    real(WP), dimension( d%nc(1), d%np(2), d%nc(3) ) :: m2_rhs_implicit0 ! rhs for momentum-y at (xc, yp, zc)
    real(WP), dimension( d%nc(1), d%nc(2), d%np(3) ) :: m3_rhs_implicit0 ! rhs for momentum-z at (xc, yc, zp)

    integer(4), parameter :: II = 1, JJ = 2, KK = 3
    real(WP)              :: one_third_rre, two_third_rre, two_rre

!===============================================================================
! Initilisation
!===============================================================================
    one_third_rre = ONE_THIRD * f%rre
    two_third_rre = TWO_THIRD * f%rre
    two_rre       = TWO * f%rre

    f%m1_rhs(:, :, :) = ZERO
    f%m2_rhs(:, :, :) = ZERO
    f%m3_rhs(:, :, :) = ZERO

    m1_rhs_implicit(:, :, :) = ZERO
    m2_rhs_implicit(:, :, :) = ZERO
    m3_rhs_implicit(:, :, :) = ZERO

    if(ithermo == 1) then
      div(:, :, :) = ZERO
    end if
      
!===============================================================================
! interpolation
!===============================================================================
!_______________________________________________________________________________
! interpolation operation in x direction
!_______________________________________________________________________________
    call Get_x_midp_P2C_3dArray ( d, f%qx, qxxc )
    call Get_x_midp_C2P_3dArray ( d, f%qy, qyxp )
    call Get_x_midp_C2P_3dArray ( d, f%qz, qzxp )
    if(ithermo == 1) then
      call Get_x_midp_P2C_3dArray ( d, f%gx,   gxxc )
      call Get_x_midp_C2P_3dArray ( d, f%gy,   gyxp )
      call Get_x_midp_C2P_3dArray ( d, f%gz,   gzxp )
      call Get_x_midp_C2P_3dArray ( d, f%mVisc, mxp )
    end if

!_______________________________________________________________________________
! interpolation  operation in y direction
!_______________________________________________________________________________
    call Get_y_midp_C2P_3dArray ( d, f%qx, qxyp ) 
    call Get_y_midp_P2C_3dArray ( d, f%qy, qyyc )
    call Get_y_midp_C2P_3dArray ( d, f%qz, qzyp )

    if(ithermo == 1) then
      call Get_y_midp_C2P_3dArray ( d, f%gx,   gxyp )
      call Get_y_midp_P2C_3dArray ( d, f%gy,   gyyc )
      call Get_y_midp_C2P_3dArray ( d, f%gz,   gzyp )
      call Get_y_midp_C2P_3dArray ( d, f%mVisc, myp )
    end if
!_______________________________________________________________________________
! interpolation  operation in z direction
!_______________________________________________________________________________
    call Get_z_midp_C2P_3dArray ( d, f%qx, qxzp ) 
    call Get_z_midp_C2P_3dArray ( d, f%qy, qyzp )
    call Get_z_midp_P2C_3dArray ( d, f%qz, qzzc )

    if(ithermo == 1) then
      call Get_z_midp_C2P_3dArray ( d, f%gx,   gxzp )
      call Get_z_midp_C2P_3dArray ( d, f%gy,   gyzp )
      call Get_z_midp_P2C_3dArray ( d, f%gz,   gzzc )
      call Get_z_midp_C2P_3dArray ( d, f%mVisc, mzp )
    end if

!===============================================================================
! dmdx at points (preparation)
!===============================================================================
    if(ithermo == 1) then
!_______________________________________________________________________________
! dmyp/dx & dmzp/dx & d(qx)/dx,  operation in x direction
!_______________________________________________________________________________
      call Get_x_1st_derivative_C2P_3dArray( d, f%mVisc, dmdx_xp )
      call Get_x_1st_derivative_C2C_3dArray( d, myp,     dmdx_yp )
      call Get_x_1st_derivative_C2C_3dArray( d, mzp,     dmdx_zp )
      call Get_x_1st_derivative_P2C_3dArray( d, f%qx,    div0    )
      div = div + div0
!_______________________________________________________________________________
! dmxp/dy & dmzp/dy & d(qy)/dy, operation in y direction
!_______________________________________________________________________________
      call Get_y_1st_derivative_C2C_3dArray( d, mxp,     dmdy_xp )
      call Get_y_1st_derivative_C2P_3dArray( d, f%mVisc, dmdy_yp )
      call Get_y_1st_derivative_C2C_3dArray( d, mzp,     dmdy_zp )
      call Get_y_1st_derivative_P2C_3dArray( d, f%qy,    div0    )
      div = div + div0
!_______________________________________________________________________________
! dmxp/dz & dmyp/dz operation in z direction
!_______________________________________________________________________________
      call Get_z_1st_derivative_C2C_3dArray( d, mxp,     dmdz_xp )
      call Get_z_1st_derivative_C2C_3dArray( d, myp,     dmdz_yp )
      call Get_z_1st_derivative_C2P_3dArray( d, f%mVisc, dmdz_zp )
      call Get_z_1st_derivative_P2C_3dArray( d, f%qz,    div0    )
      div = div + div0
    end if

!===============================================================================
! the RHS of momentum equation
!===============================================================================
!-------------------------------------------------------------------------------
! the RHS terms of all 3 momentum equations operating in the x direction
!_______________________________________________________________________________
    if(ithermo == 0 ) then

      ! for x-mom convection term (x-c1/3): d(qx * qx)/dx at (i', j, k)
      call Get_x_1st_derivative_P2P_3dArray( d, -f%qx * f%qx, m1_rhs )
      f%m1_rhs = f%m1_rhs + m1_rhs

      ! for y-mom convection term (y-c1/3), d(qx * qy)/dx at (i, j', k)
      call Get_x_1st_derivative_P2C_3dArray( d, -qxyp * qyxp, m2_rhs )
      f%m2_rhs = f%m2_rhs + m2_rhs

      ! for z-mom convection term (z-c1/3), d(qx * qz)/dx at (i, j, k')
      call Get_x_1st_derivative_P2C_3dArray( d, -qxzp * qzxp, m3_rhs )
      f%m3_rhs = f%m3_rhs + m3_rhs

      ! for x-mom diffusion term (x-v1/1), \mu * Ljj(ux) at (i', j, k)
      call Get_x_2nd_derivative_P2P_3dArray( d, f%qx, m1_rhs )
      f%m1_rhs = f%m1_rhs + f%rre * m1_rhs

    else if(ithermo == 1) then

      ! for x-mom convection term (x-c1/3): d(gx * qx)/dx at (i', j, k)
      call Get_x_1st_derivative_P2P_3dArray( d, -f%gx * f%qx, m1_rhs )
      f%m1_rhs = f%m1_rhs + m1_rhs

      ! for y-mom convection term (y-c1/3), d(gx * qy)/dx at (i, j', k)
      call Get_x_1st_derivative_P2C_3dArray( d, -gxyp * qyxp, m2_rhs )
      f%m2_rhs = f%m2_rhs + m2_rhs

      ! for z-mom convection term (z-c1/3), d(gx * qz)/dx at (i, j, k')
      call Get_x_1st_derivative_P2C_3dArray( d, -gxzp * qzxp, m3_rhs )
      f%m3_rhs = f%m3_rhs + m3_rhs

      ! for x-mom diffusion term (x-v1/7), \mu * Ljj(ux) at (i', j, k)
      call Get_x_2nd_derivative_P2P_3dArray( d, f%qx, m1_rhs )
      f%m1_rhs = f%m1_rhs + f%rre * mxp * m1_rhs

      ! for x-mom diffusion term (x-v2/7), \mu * 1/3 * d (div)/dx at (i', j, k)
      call Get_x_1st_derivative_C2P_3dArray( d, div, m1_rhs )
      f%m1_rhs = f%m1_rhs + one_third_rre * mxp * m1_rhs

      ! for x-mom diffusion term (x-v3/7), 2d\mu/dx * (-1/3 * div(u)) +  2d\mu/dx * du/dx
      call Get_x_midp_C2P_3dArray          ( d, div, m1_rhs )
      f%m1_rhs = f%m1_rhs - two_third_rre * dmdx_xp * m1_rhs
      call Get_x_1st_derivative_P2P_3dArray( d, f%qx, m1_rhs )
      f%m1_rhs = f%m1_rhs + two_rre * dmdx_xp * m1_rhs

      ! for x-mom diffusion term (x-v4/7), d(mu)/dy * d(qy)/dx at (i', j, k)
      call Get_x_1st_derivative_C2P_3dArray( d, qyyc, m1_rhs )
      f%m1_rhs =  f%m1_rhs + f%rre * dmdy_xp * m1_rhs

      ! for x-mom diffusion term (x-v6/7), d(mu)/dz * d(qz)/dx at (i', j, k)
      call Get_x_1st_derivative_C2P_3dArray( d, qzzc, m1_rhs )
      f%m1_rhs =  f%m1_rhs + f%rre * dmdz_xp * m1_rhs

      ! for y-mom diffusion term (y-v5/7), d(mu)/dx * d(qy))/dx at (i, j', k)
      call Get_x_1st_derivative_C2C_3dArray( d, f%qy, m2_rhs )
      f%m2_rhs =  f%m2_rhs + f%rre * dmdx_yp * m2_rhs

      ! for z-mom diffusion term (z-v5/7), d(mu)/dx * d(qz)/dx at (i, j, k')
      call Get_x_1st_derivative_C2C_3dArray( d, f%qz, m3_rhs )
      f%m3_rhs =  f%m3_rhs + f%rre * dmdx_zp * m3_rhs
    else
    end if

    ! pressure gradient in x direction, d(sigma_1 p)
    call Get_x_1st_derivative_C2P_3dArray( d, sigma1p * f%pres, m1_rhs_implicit0 )
    m1_rhs_implicit =  m1_rhs_implicit - m1_rhs_implicit0

    ! gravity force in x direction
    if( ithermo == 1 .and. ( igravity == 1 .or. igravity == -1) ) then
      call Get_x_midp_C2P_3dArray( d, f%dDens, m1_rhs_implicit0 )
      m1_rhs_implicit =  m1_rhs_implicit + f%fgravity * m1_rhs_implicit0
    end if

!-------------------------------------------------------------------------------
! the RHS terms of all 3 momentum equations operating in the y direction
!_______________________________________________________________________________ 
    if(ithermo == 0 ) then

      ! for x-mom convection term (x-c2/3): d(qy * qx)/dy at (i', j, k)
      call Get_y_1st_derivative_P2C_3dArray( d, -qyxp * qxyp,  m1_rhs )
      f%m1_rhs = f%m1_rhs + m1_rhs

      ! for y-mom convection term (y-c2/3), d(qy * qy)/dy at (i, j', k)
      call Get_y_1st_derivative_P2P_3dArray( d, -f%qy * f%qy,  m2_rhs )
      f%m2_rhs = f%m2_rhs + m2_rhs

      ! for z-mom convection term (z-c2/3), d(qy * qz)/dy at (i, j, k')
      call Get_y_1st_derivative_P2C_3dArray( d, -qyzp * qzyp,  m3_rhs )
      f%m3_rhs = f%m3_rhs + m3_rhs

      ! for y-mom diffusion term (y-v1/1), \mu * Ljj(uy) at (i, j', k)
      call Get_y_2nd_derivative_P2P_3dArray( d, f%qy,  m2_rhs )
      f%m2_rhs = f%m2_rhs + f%rre * m2_rhs

    else if (ithermo == 1) then

      ! for x-mom convection term (x-c2/3): d(gy * qx)/dy at (i', j, k)
      call Get_y_1st_derivative_P2C_3dArray( d, -gyxp * qxyp,  m1_rhs )
      f%m1_rhs = f%m1_rhs + m1_rhs

      ! for y-mom convection term (y-c2/3), d(gy * qy)/dy at (i, j', k)
      call Get_y_1st_derivative_P2P_3dArray( d, -f%gy * f%qy,  m2_rhs )
      f%m2_rhs = f%m2_rhs + m2_rhs

      ! for z-mom convection term (z-c2/3), d(gy * qz)/dy at (i, j, k')
      call Get_y_1st_derivative_P2C_3dArray( d, -gyzp * qzyp,  m3_rhs )
      f%m3_rhs = f%m3_rhs + m3_rhs

      ! for y-mom diffusion term (y-v1/7), \mu * Ljj(uy) at (i, j', k)
      call Get_y_2nd_derivative_P2P_3dArray( d, f%qy,  m2_rhs )
      f%m2_rhs = f%m2_rhs + f%rre * myp * m2_rhs

      ! for y-mom diffusion term (y-v2/7), \mu * 1/3 * d (div)/dy at (i, j', k)
      call Get_y_1st_derivative_C2P_3dArray( d, div, m2_rhs )
      f%m2_rhs = f%m2_rhs + one_third_rre * myp * m2_rhs

      ! for y-mom diffusion term (y-v3/7), 2d\mu/dy * (-1/3 * div(u)) +  2d\mu/dy * dv/dy
      call Get_y_midp_C2P_3dArray          ( d, div, m2_rhs )
      f%m2_rhs = f%m2_rhs - two_third_rre * dmdy_yp * m2_rhs
      call Get_y_1st_derivative_P2P_3dArray( d, f%qy, m2_rhs )
      f%m2_rhs = f%m2_rhs + two_rre * dmdy_yp * m2_rhs

      ! for y-mom diffusion term (y-v4/7), d(mu)/dx * d(qx)/dy at (i, j', k)
      call Get_y_1st_derivative_C2P_3dArray( d, qxxc, m2_rhs )
      f%m2_rhs =  f%m2_rhs + f%rre * dmdx_yp * m2_rhs

      ! for y-mom diffusion term (y-v6/7), d(mu)/dz * d(qz)/dy at (i, j', k)
      call Get_y_1st_derivative_C2P_3dArray( d, qzzc, m2_rhs )
      f%m2_rhs =  f%m2_rhs + f%rre * dmdz_yp * m2_rhs

      ! for x-mom diffusion term (x-v5/7), d(mu)/dy * d(qx)/dy at (i', j, k)
      call Get_y_1st_derivative_C2C_3dArray( d, f%qx, m1_rhs )
      f%m1_rhs =  f%m1_rhs + f%rre * dmdy_xp * m1_rhs

      ! for z-mom diffusion term (z-v7/7), d(mu)/dy * d(qz)/dy at (i, j, k')
      call Get_y_1st_derivative_C2C_3dArray( d, f%qz, m3_rhs )
      f%m3_rhs =  f%m3_rhs + f%rre * dmdy_zp * m3_rhs

    else
    end if

    ! pressure gradient in y direction, d(sigma_1 p)
    call Get_y_1st_derivative_C2P_3dArray( d, sigma1p * f%pres, m2_rhs_implicit0 )
    m2_rhs_implicit =  m2_rhs_implicit - m2_rhs_implicit0

    ! gravity force in y direction
    if( ithermo == 1 .and. ( igravity == 2 .or. igravity == -2) ) then
      call Get_y_midp_C2P_3dArray( d, f%dDens, m2_rhs_implicit0 )
      m2_rhs_implicit =  m2_rhs_implicit + f%fgravity * m2_rhs_implicit0
    end if
!-------------------------------------------------------------------------------
! the RHS terms of all 3 momentum equations operating in the z direction
!_______________________________________________________________________________
    if(ithermo == 0 ) then

      ! for x-mom convection term (x-c3/3): d(qz * qx)/dz at (i', j, k)
      call Get_z_1st_derivative_P2C_3dArray( d, -qzxp * qxzp,  m1_rhs )
      f%m1_rhs = f%m1_rhs + m1_rhs

      ! for y-mom convection term (y-c3/3), d(qz * qy)/dz at (i, j', k)
      call Get_z_1st_derivative_P2C_3dArray( d, -qzyp * qyzp,  m2_rhs )
      f%m2_rhs = f%m2_rhs + m2_rhs

      ! for z-mom convection term (z-c3/3), d(qz * qz)/dz at (i, j, k')
      call Get_z_1st_derivative_P2P_3dArray( d, -f%qz * f%qz,  m3_rhs )
      f%m3_rhs = f%m3_rhs + m3_rhs

      ! for z-mom diffusion term (z-v1/1), \mu * Ljj(uz) at (i, j, k')
      call Get_z_2nd_derivative_P2P_3dArray( d, f%qz,  m3_rhs )
      f%m3_rhs = f%m3_rhs + f%rre * m3_rhs

    else if (ithermo == 1) then

      ! for x-mom convection term (x-c3/3): d(gz * qx)/dz at (i', j, k)
      call Get_z_1st_derivative_P2C_3dArray( d, -gzxp * qxzp,  m1_rhs )
      f%m1_rhs = f%m1_rhs + m1_rhs

      ! for y-mom convection term (y-c3/3), d(gz * qy)/dz at (i, j', k)
      call Get_z_1st_derivative_P2C_3dArray( d, -gzyp * qyzp,  m2_rhs )
      f%m2_rhs = f%m2_rhs + m2_rhs

      ! for z-mom convection term (z-c3/3), d(gz * qz)/dz at (i, j, k')
      call Get_z_1st_derivative_P2P_3dArray( d, -f%gz * f%qz,  m3_rhs )
      f%m3_rhs = f%m3_rhs + m3_rhs

      ! for z-mom diffusion term (z-v1/7), \mu * Ljj(uz) at (i, j, k')
      call Get_z_2nd_derivative_P2P_3dArray( d, f%qz,  m3_rhs )
      f%m3_rhs = f%m3_rhs + f%rre * mzp * m3_rhs

      ! for z-mom diffusion term (z-v2/7), \mu * 1/3 * d (div)/dz at (i, j, k')
      call Get_z_1st_derivative_C2P_3dArray( d, div, m3_rhs )
      f%m3_rhs = f%m3_rhs + one_third_rre * mzp * m3_rhs

      ! for z-mom diffusion term (z-v3/7), 2d\mu/dz * (-1/3 * div(u)) +  2d\mu/dz * dw/dz
      call Get_z_midp_C2P_3dArray          ( d, div, m3_rhs )
      f%m3_rhs = f%m3_rhs - two_third_rre * dmdz_zp * m3_rhs
      call Get_z_1st_derivative_P2P_3dArray( d, f%qz, m3_rhs )
      f%m3_rhs = f%m3_rhs + two_rre * dmdz_zp * m3_rhs

      ! for z-mom diffusion term (z-v4/7), d(mu)/dx * d(qx)/dz at (i, j, k')
      call Get_z_1st_derivative_C2P_3dArray( d, qxxc, m3_rhs )
      f%m3_rhs =  f%m3_rhs + f%rre * dmdx_zp * m3_rhs

      ! for z-mom diffusion term (z-v6/7), d(mu)/dy * d(qy)/dz at (i, j, k')
      call Get_z_1st_derivative_C2P_3dArray( d, qyyc, m3_rhs )
      f%m3_rhs =  f%m3_rhs + f%rre * dmdy_zp * m3_rhs

      ! for x-mom diffusion term (x-v7/7), d(mu)/dz * d(qx)/dz at (i', j, k)
      call Get_z_1st_derivative_C2C_3dArray( d, f%qx, m1_rhs )
      f%m1_rhs =  f%m1_rhs + f%rre * dmdz_xp * m1_rhs

      ! for y-mom diffusion term (y-v7/7), d(mu)/dz * d(qy)/dz at (i, j', k)
      call Get_z_1st_derivative_C2C_3dArray( d, f%qy, m2_rhs )
      f%m2_rhs =  f%m2_rhs + f%rre * dmdz_yp * m2_rhs

    else
    end if

    ! pressure gradient in z direction, d(sigma_1 p)
    call Get_z_1st_derivative_C2P_3dArray( d, sigma1p * f%pres, m3_rhs_implicit0 )
    m3_rhs_implicit =  m3_rhs_implicit - m3_rhs_implicit0

    ! gravity force in z direction
    if( ithermo == 1 .and. ( igravity == 3 .or. igravity == -3) ) then
      call Get_z_midp_C2P_3dArray( d, f%dDens, m3_rhs_implicit0 )
      m3_rhs_implicit =  m3_rhs_implicit + f%fgravity * m3_rhs_implicit0
    end if

!-------------------------------------------------------------------------------
! to build up rhs in total, in all directions
!_______________________________________________________________________________ 
    ! x-momentum
    call Calculate_momentum_fractional_step(f%m1_rhs0, f%m1_rhs, m1_rhs_implicit, isub)
    if(idriven /= IDRVF_NO) call Calculate_momentum_driven_source(f%m1_rhs, d, isub) 

    ! y-momentum
    call Calculate_momentum_fractional_step(f%m2_rhs0, f%m2_rhs, m2_rhs_implicit, isub)

    ! z-momentum
    call Calculate_momentum_fractional_step(f%m3_rhs0, f%m3_rhs, m3_rhs_implicit, isub)
 
    return
  end subroutine Compute_momentum_rhs

!===============================================================================
!===============================================================================
!> \brief To update the provisional u or rho u.
!>
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[inout]  rhs          the rhs
!> \param[inout]  u            provisional u or rho u.
!_______________________________________________________________________________
  subroutine Calculate_intermediate_mvar(rhs, u)
    implicit none
    real(WP), dimension(:, :, :), intent(inout) :: rhs, u

    u(:, :, :) = u(:, :, :) + rhs(:, :, :)

    return
  end subroutine Calculate_intermediate_mvar
!===============================================================================
!===============================================================================
  subroutine Correct_massflux(ux, uy, uz, phi, d, isub)
    use udf_type_mod,      only : t_domain
    use input_general_mod, only : tAlpha, dt, sigma2p
    use operations
    implicit none

    type(t_domain), intent(in   ) :: d
    integer(4),     intent(in   ) :: isub
    real(WP), dimension( d%np(1), d%nc(2), d%nc(3) ), intent(inout) :: ux
    real(WP), dimension( d%nc(1), d%np(2), d%nc(3) ), intent(inout) :: uy
    real(WP), dimension( d%nc(1), d%nc(2), d%np(3) ), intent(inout) :: uz
    real(WP), dimension( d%nc(1), d%nc(2), d%nc(3) ), intent(in   ) :: phi

    real(WP), dimension( d%np(1), d%nc(2), d%nc(3) ) :: dphidx
    real(WP), dimension( d%nc(1), d%np(2), d%nc(3) ) :: dphidy
    real(WP), dimension( d%nc(1), d%nc(2), d%np(3) ) :: dphidz

  
    call Get_x_1st_derivative_C2P_3dArray( d, phi,  dphidx )
    ux = ux - dt * tAlpha(isub) * sigma2p * dphidx

    call Get_y_1st_derivative_C2P_3dArray( d, phi,  dphidy )
    uy = uy - dt * tAlpha(isub) * sigma2p * dphidy

    call Get_z_1st_derivative_C2P_3dArray( d, phi,  dphidz )
    uz = uz - dt * tAlpha(isub) * sigma2p * dphidz

    return
  end subroutine Correct_massflux
!===============================================================================
!===============================================================================
!> \brief To update the provisional u or rho u.
!>
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[inout]  f            flow field
!> \param[inout]  d            domain
!> \param[in]     isub         RK sub-iteration
!_______________________________________________________________________________
  subroutine Solve_momentum_eq(f, d, isub)
    use input_general_mod, only : iviscous, IVIS_SEMIMPLT, IVIS_EXPLICIT, ithermo
    use udf_type_mod,      only : t_flow, t_domain
    use typeconvert_mod
    use continuity_eq_mod
    use poisson_mod
    use boundary_conditions_mod
    implicit none

    type(t_flow),   intent(inout) :: f
    type(t_domain), intent(in   ) :: d
    integer(4),     intent(in   ) :: isub

!-------------------------------------------------------------------------------
! to calculate the rhs of the momenturn equation in stepping method
!_______________________________________________________________________________ 
    call Compute_momentum_rhs(f, d, isub)
!-------------------------------------------------------------------------------
! to update intermediate (\hat{q}) or (\hat{g})
!_______________________________________________________________________________
 
    if(iviscous == IVIS_EXPLICIT) then

      if(ithermo == 0) then 
        call Calculate_intermediate_mvar(f%m1_rhs, f%qx)
        call Calculate_intermediate_mvar(f%m2_rhs, f%qy)
        call Calculate_intermediate_mvar(f%m3_rhs, f%qz)
      else
        call Calculate_intermediate_mvar(f%m1_rhs, f%gx)
        call Calculate_intermediate_mvar(f%m2_rhs, f%gy)
        call Calculate_intermediate_mvar(f%m3_rhs, f%gz)
      end if

    else if(iviscous == IVIS_SEMIMPLT) then
      !in order for a high order spacial accuracy
      ! to use Alternating direction implicit method
      ! ref: Cui2013: Convergence analysis of high-order compact 
      ! alternating direction implicit schemes for the two-dimensional 
      ! time fractional equation
      stop
    else 

    end if
!-------------------------------------------------------------------------------
! to update b.c. values
!-------------------------------------------------------------------------------
    call Apply_BC_velocity (f%gx, f%gy, f%gz, d)
    call Apply_BC_velocity (f%qx, f%qy, f%qz, d)
!-------------------------------------------------------------------------------
! to calculate the provisional divergence constrains
!-------------------------------------------------------------------------------
    !call Print_debug_mid_msg("  Computing provisional divergence constrains ...")
    call Calculate_continuity_constrains(f, d, isub)
!-------------------------------------------------------------------------------
! to solve Poisson equation
!-------------------------------------------------------------------------------
    !call Print_debug_mid_msg("  Solving Poisson Equation ...")
    call Solve_poisson(f%pcor)
!-------------------------------------------------------------------------------
! to update velocity/massflux correction
!-------------------------------------------------------------------------------
    !call Print_debug_mid_msg("  Updating velocity/mass flux ...")
    if(ithermo == 0) then 
      call Correct_massflux(f%qx, f%qy, f%qz, f%pcor, d, isub)
    else
      call Correct_massflux(f%gx, f%gy, f%gz, f%pcor, d, isub)
    end if
!-------------------------------------------------------------------------------
! to update pressure
!-------------------------------------------------------------------------------
    f%pres = f%pres + f%pcor
!-------------------------------------------------------------------------------
! to update b.c. values
!-------------------------------------------------------------------------------
    call Apply_BC_velocity (f%gx, f%gy, f%gz, d)
    call Apply_BC_velocity (f%qx, f%qy, f%qz, d)

    return
  end subroutine

end module eq_momentum_mod
