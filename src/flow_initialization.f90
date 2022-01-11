!-------------------------------------------------------------------------------
!                      CHAPSim version 2.0.0
!                      --------------------------
! This file is part of CHAPSim, a general-purpose CFD tool.
!
! This program is free software; you can redistribute it and/or modify it under
! the terms of the GNU General Public License as published by the Free Software
! Foundation; either version 3 of the License, or (at your option) any later
! version.
!
! This program is distributed in the hope that it will be useful, but WITHOUT
! ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
! FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
! details.
!
! You should have received a copy of the GNU General Public License along with
! this program; if not, write to the Free Software Foundation, Inc., 51 Franklin
! Street, Fifth Floor, Boston, MA 0type t_domain=============================================
!> \file flow_initialisation.f90
!>
!> \brief Define and initialise flow and thermal variables.
!>
!===============================================================================
module flow_variables_mod
  use type_vars_mod
  implicit none

  
  private :: Generate_poiseuille_flow_profile
  private :: Initialize_poiseuille_flow
  private :: Initialize_vortexgreen_2dflow
  private :: Initialize_vortexgreen_3dflow
  private :: Initialize_thermal_variables

  public  :: Calculate_xbulk_velocity
  public  :: Check_maximum_velocity
  public  :: Allocate_thermoflow_variables
  public  :: Initialize_flow_variables
  public  :: Calculate_RePrGr
  public  :: Validate_TGV2D_error

contains
!===============================================================================
!===============================================================================
!> \brief Allocate flow and thermal variables.     
!>
!> This subroutine is called once at beginning of solver.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[in]     none          NA
!> \param[out]    none          NA
!_______________________________________________________________________________
  subroutine Allocate_thermoflow_variables (domain, flow, thermo)
    !use domain_decomposition_mod
    use input_general_mod,       only : ithermo
    use parameters_constant_mod, only : ZERO, ONE
    implicit none

    type(t_domain), intent(in)    :: domain
    type(t_flow),   intent(inout) :: flow
    type(t_thermo), intent(inout) :: thermo

    call Print_debug_start_msg("Allocating flow and thermal variables ...")

!_______________________________________________________________________________
! x pencil
!_______________________________________________________________________________
    allocate ( flow%qx( domain%np(1), domain%nc(2), domain%nc(3) ) )
    allocate ( flow%qy( domain%nc(1), domain%np(2), domain%nc(3) ) )
    allocate ( flow%qz( domain%nc(1), domain%nc(2), domain%np(3) ) )
    flow%qx = ZERO
    flow%qy = ZERO
    flow%qz = ZERO

    allocate ( flow%gx( domain%np(1), domain%nc(2), domain%nc(3) ) )
    allocate ( flow%gy( domain%nc(1), domain%np(2), domain%nc(3) ) )
    allocate ( flow%gz( domain%nc(1), domain%nc(2), domain%np(3) ) )
    flow%gx = ZERO
    flow%gy = ZERO
    flow%gz = ZERO

    allocate ( flow%pres( domain%nc(1), domain%nc(2), domain%nc(3) ) )
    allocate ( flow%pcor( domain%nc(1), domain%nc(2), domain%nc(3) ) )
    flow%pres = ZERO
    flow%pcor = ZERO

    allocate ( flow%dDens( domain%nc(1), domain%nc(2), domain%nc(3) ) )
    allocate ( flow%mVisc( domain%nc(1), domain%nc(2), domain%nc(3) ) )
    flow%dDens = ONE
    flow%mVisc = ONE

    allocate ( flow%dDensm1( domain%nc(1), domain%nc(2), domain%nc(3) ) )
    allocate ( flow%dDensm2( domain%nc(1), domain%nc(2), domain%nc(3) ) )
    flow%dDensm1 = ONE
    flow%dDensm2 = ONE

    allocate ( flow%m1_rhs( domain%np(1), domain%nc(2), domain%nc(3) ) )
    allocate ( flow%m2_rhs( domain%nc(1), domain%np(2), domain%nc(3) ) )
    allocate ( flow%m3_rhs( domain%nc(1), domain%nc(2), domain%np(3) ) )
    flow%m1_rhs = ZERO
    flow%m2_rhs = ZERO
    flow%m3_rhs = ZERO

    allocate ( flow%m1_rhs0( domain%np(1), domain%nc(2), domain%nc(3) ) )
    allocate ( flow%m2_rhs0( domain%nc(1), domain%np(2), domain%nc(3) ) )
    allocate ( flow%m3_rhs0( domain%nc(1), domain%nc(2), domain%np(3) ) )
    flow%m1_rhs0 = ZERO
    flow%m2_rhs0 = ZERO
    flow%m3_rhs0 = ZERO

    if(ithermo == 1) then
      allocate ( thermo%dh    ( domain%nc(1), domain%nc(2), domain%nc(3) ) )
      allocate ( thermo%hEnth ( domain%nc(1), domain%nc(2), domain%nc(3) ) )
      allocate ( thermo%kCond ( domain%nc(1), domain%nc(2), domain%nc(3) ) )
      allocate ( thermo%tTemp ( domain%nc(1), domain%nc(2), domain%nc(3) ) )
      thermo%dh    = ZERO
      thermo%hEnth = ZERO
      thermo%kCond = ONE
      thermo%tTemp = ONE
    end if

    call Print_debug_end_msg
    return
  end subroutine Allocate_thermoflow_variables
!===============================================================================
!===============================================================================
!> \brief Initialise thermal variables if ithermo = 1.     
!>
!> This subroutine is called once.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[inout]  f             flow type
!> \param[inout]  t             thermo type
!_______________________________________________________________________________
  subroutine Initialize_thermal_variables (f, t)
    use input_general_mod, only : tiRef, t0Ref
    use input_thermo_mod, only : tpIni
    implicit none
    type(t_flow),   intent(inout) :: f
    type(t_thermo), intent(inout) :: t
    logical :: is_dim
  
    tpIni%t = tiRef / t0Ref
    is_dim = .false.
    call tpIni%Refresh_thermal_properties_from_T(is_dim)

    f%dDens(:, :, :)  = tpIni%d
    f%mVisc(:, :, :)  = tpIni%m

    t%dh    = tpIni%dh
    t%hEnth = tpIni%h
    t%kCond = tpIni%k
    t%tTemp = tpIni%t

    return
  end subroutine Initialize_thermal_variables
!===============================================================================
!===============================================================================
!> \brief The main code for initializing flow variables
!>
!> This subroutine is only for pre-processing/post-processing 2nd order only.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[inout]  none          NA
!_______________________________________________________________________________
  subroutine Calculate_xbulk_velocity(u, d, ubulk)
    use parameters_constant_mod, only : ZERO, HALF
    use operations,              only : Get_midp_interpolation_1D, &
                                       Get_volumetric_average_3d
    implicit none

    type(t_domain), intent(in ) :: d
    real(WP),       intent(in ) :: u(:, :, :)
    real(WP),       intent(out) :: ubulk

    logical :: is_stored_nyp
    is_stored_nyp = .false.

    call Get_volumetric_average_3d(d, u, ubulk, is_stored_nyp)
    
    Call Print_debug_mid_msg("  The bulk velocity is:")
    write(*, '(5X, A, 1ES13.5)') 'Ubulk : ', ubulk

    return
  end subroutine
!===============================================================================
!===============================================================================
!> \brief Generate a flow profile for Poiseuille flow in channel or pipe.     
!>
!> This subroutine is called locally once.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[in]     d             domain
!> \param[out]    u_laminar     velocity profile along wall-normal direction
!_______________________________________________________________________________
  subroutine Generate_poiseuille_flow_profile(u_laminar, d)
    use parameters_constant_mod, only : ZERO, ONE, ONEPFIVE, TWO, MAXP, TRUNCERR
    use input_general_mod
    use udf_type_mod
    use math_mod
    implicit none

    type(t_domain), intent(in)  :: d
    real(WP),       intent(out) :: u_laminar(:)
    
    real(WP)   :: a, b, c, yy, ymax, ymin
    integer(4) :: j
    

    u_laminar (:) = ZERO

    ymax = d%yp( d%np_geo(2) )
    ymin = d%yp( 1 )
    if (d%case == ICASE_CHANNEL) then
      a = (ymax - ymin) / TWO
      b = ZERO
      c = ONEPFIVE
    else if (d%case == ICASE_PIPE) then
      a = (ymax - ymin)
      b = ZERO
      c = TWO
    else if (d%case == ICASE_ANNUAL) then
      a = (ymax - ymin) / TWO
      b = (ymax + ymin) / TWO
      c = TWO
    else 
      a = MAXP
      b = ZERO
      c = ONE
    end if

    do j = 1, d%nc(2)
      yy = d%yc(j)
      u_laminar(j) = ( ONE - ( (yy - b)**2 ) / a / a ) * c
    end do

    return
  end subroutine Generate_poiseuille_flow_profile
!===============================================================================
!===============================================================================
!> \brief Initialize Poiseuille flow in channel or pipe.     
!>
!> This subroutine is called locally once.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[in]     d             domain
!> \param[out]    f             flow
!_______________________________________________________________________________
  subroutine Initialize_poiseuille_flow(ux, uy, uz, p, d)
    use random_number_generation_mod
    use parameters_constant_mod, only : ZERO, ONE
    use input_general_mod
    use udf_type_mod
    use boundary_conditions_mod
    implicit none
    type(t_domain), intent(in   ) :: d
    real(WP),       intent(inout) :: ux(:, :, :) , &
                                     uy(:, :, :) , &
                                     uz(:, :, :) , &
                                     p (:, :, :)            
    
    real(WP), allocatable, dimension(:) :: u_laminar
    integer :: i, j, k
    integer :: seed
    real(WP) :: rd(3)
    integer :: pf_unit
    real(WP) :: uxa, uya, uza, ubulk

!===============================================================================
!   to get Poiseuille profile
!===============================================================================
    allocate ( u_laminar ( d%nc(2) ) ); u_laminar(:) = ZERO
    call Generate_poiseuille_flow_profile ( u_laminar, d )

    p (:, :, :) = ZERO
    ux(:, :, :) = ZERO
    uy(:, :, :) = ZERO
    uz(:, :, :) = ZERO
!===============================================================================
!   to get random fields [-1,1]
!===============================================================================
    seed = 0 ! real random
    do k = 1, d%nc(3)
      do j = 1, d%nc(2)
        do i = 1, d%nc(1)
          seed = seed + k + j + i ! repeatable random
          call Initialize_random_number ( seed )
          call Generate_rvec_random( -ONE, ONE, 3, rd)
          ux(i, j, k) = initNoise * rd(1)
          uy(i, j, k) = initNoise * rd(2)
          uz(i, j, k) = initNoise * rd(3)
        end do
      end do
    end do
    call Apply_BC_velocity(ux, uy, uz, d)
!===============================================================================
!   The x-z plane averaged should be zero
!===============================================================================
    do j = 1, d%nc(2)
      uxa = sum( ux( 1:d%nc(1), j, 1:d%nc(3) ) )
      uya = sum( uy( 1:d%nc(1), j, 1:d%nc(3) ) )
      uza = sum( uz( 1:d%nc(1), j, 1:d%nc(3) ) )
      uxa = uxa / real(d%nc(1) * d%nc(3), WP)
      uza = uza / real(d%nc(1) * d%nc(3), WP)
      uya = uya / real(d%nc(1) * d%nc(3), WP)
      ux(:, j, :) = ux(:, j, :) - uxa + u_laminar(j)
      uy(:, j, :) = uy(:, j, :) - uya
      uz(:, j, :) = uz(:, j, :) - uza
      !write(*, *) 'inif', ux(1, j, 1), uy(1, j, 1), uz(1, j, 1) ! test
    end do
    call Apply_BC_velocity(ux, uy, uz, d)

    ! unified bulk
    call Calculate_xbulk_velocity(ux, d, ubulk)
    ux(:, :, :) = ux(:, :, :) / ubulk

    call Apply_BC_velocity(ux, uy, uz, d)

    call Calculate_xbulk_velocity(ux, d, ubulk)
    ! to write out velocity profile
    open ( newunit = pf_unit,     &
           file    = 'output_check_poiseuille_profile.dat', &
           status  = 'replace',         &
           action  = 'write')
    ! check the bulk velocity is one
    write(pf_unit, '(A)') "# :yc, ux_laminar, ux, uy, uz"
    do j = 1, d%nc(2)
      write(pf_unit, '(5ES13.5)') d%yc(j), u_laminar(j), ux(d%nc(1)/2, j, d%nc(3)/2), &
                                  uy(d%nc(1)/2, j, d%nc(3)/2), uz(d%nc(1)/2, j, d%nc(3)/2)
    end do
    close(pf_unit)
    
    deallocate (u_laminar)
    return
  end subroutine  Initialize_poiseuille_flow
!===============================================================================
!===============================================================================
!> \brief Initialize Vortex Green flow
!>
!> This subroutine is called locally once.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[in]     d             domain
!> \param[out]    f             flow
!_______________________________________________________________________________
  subroutine  Initialize_vortexgreen_2dflow(ux, uy, uz, p, d)
    use parameters_constant_mod!, only : HALF, ZERO, SIXTEEN, TWO
    use udf_type_mod
    use math_mod
    implicit none

    type(t_domain), intent(in   ) :: d
    real(WP),       intent(inout) :: ux(:, :, :), &
                                     uy(:, :, :), &
                                     uz(:, :, :), &
                                     p (:, :, :)

    real(WP) :: xc, yc
    real(WP) :: xp, yp
    integer(4) :: i, j

    do j = 1, d%nc(2)
      yc = d%yc(j)
      do i = 1, d%np(1)
        xp = d%h(1) * real(i - 1, WP)
        ux(i, j, :) =  sin_wp ( xp ) * cos_wp ( yc )
      end do
    end do

    do j = 1, d%np(2)
      yp = d%yp(j)
      do i = 1, d%nc(1)
        xc = d%h(1) * (real(i - 1, WP) + HALF)
        uy(i, j, :) = -cos_wp ( xc ) * sin_wp ( yp )
      end do
    end do

    uz(:, :, :) =  ZERO


    do j = 1, d%nc(2)
      yc = d%yc(j)
      do i = 1, d%nc(1)
        xc = d%h(1) * (real(i - 1, WP) + HALF)
        p(i, j, :)= ( cos_wp(TWO * xc) + sin(TWO * yc) ) / FOUR
      end do
    end do
    
    return
  end subroutine Initialize_vortexgreen_2dflow

  subroutine  Validate_TGV2D_error(f, d)
    use parameters_constant_mod
    use udf_type_mod
    use math_mod
    implicit none

    type(t_domain), intent(in   ) :: d
    type(t_flow),   intent(in   ) :: f

    integer :: k, i, j
    real(wp) :: uerr, ue, uc, verr, perr
    real(wp) :: xc, yc, xp, yp
    real(wp) :: uerrmax, verrmax, perrmax

    integer :: output_unit
    character( len = 128) :: filename
    logical :: file_exists = .FALSE.
    

    filename = 'Validation_TGV2d.dat'

    INQUIRE(FILE = trim(filename), exist = file_exists)

    if(.not.file_exists) then
      open(newunit = output_unit, file = trim(filename), action = "write", status = "new")
      write(output_unit, '(A)') 'Time, SD(u), SD(v), SD(p)'
    else
      open(newunit = output_unit, file = trim(filename), action = "write", status = "old", position="append")
     end if
    ! data convert to cell centre data...


    uerr = ZERO
    uerrmax = ZERO
    do k = 1, d%nc(3)
      do j = 1, d%nc(2)
        yc = d%yc(j)
        do i = 1, d%np(1)
          xp = d%h(1) * real(i - 1, WP)
          uc = f%qx(i, j, k)
          ue = sin_wp ( xp ) * cos_wp ( yc ) * exp(- TWO * f%rre * f%time)
          uerr = uerr + (uc - ue)**2
          if(dabs(uc - ue) > uerrmax) uerrmax = dabs(uc - ue)
        end do
      end do
    end do
    uerr = uerr / real(d%np(1), wp) / real(d%nc(2), wp) / real(d%nc(3), wp)
    uerr = sqrt_wp(uerr)

    verr = ZERO
    verrmax = ZERO
    do k = 1, d%nc(3)
      do j = 1, d%np(2)
        yp = d%yp(j)
        do i = 1, d%nc(1)
          xc = d%h(1) * (real(i - 1, WP) + HALF)
          uc = f%qy(i, j, k)
          ue = - cos_wp ( xc ) * sin_wp ( yp ) * exp(- TWO * f%rre * f%time)
          verr = verr + (uc - ue)**2
          if(dabs(uc - ue) > verrmax) verrmax = dabs(uc - ue)
        end do
      end do
    end do
    verr = verr / real(d%nc(1), wp) / real(d%np(2), wp) / real(d%nc(3), wp)
    verr = sqrt_wp(verr)

    perr = ZERO
    perrmax = ZERO
    do k = 1, d%nc(3)
      do j = 1, d%np(2)
        yc = d%yc(j)
        do i = 1, d%nc(1)
          xc = d%h(1) * (real(i - 1, WP) + HALF)
          uc = f%pres(i, j, k)
          ue = ( cos_wp ( TWO * xc ) + sin_wp ( TWO * yc ) ) / FOUR * (exp(- TWO * f%rre * f%time))**2
          perr = perr + (uc - ue)**2
          if(dabs(uc - ue) > perrmax) perrmax = dabs(uc - ue)
        end do
      end do
    end do
    perr = perr / real(d%nc(1), wp) / real(d%nc(2), wp) / real(d%nc(3), wp)
    perr = sqrt_wp(perr)

    write(output_unit, '(1F10.4, 6ES15.7)') f%time, uerr, verr, perr, uerrmax, verrmax, perrmax
    close(output_unit)

    return
  end subroutine
!===============================================================================
!===============================================================================
!> \brief Initialize Vortex Green flow
!>
!> This subroutine is called locally once.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[in]     d             domain
!> \param[out]    f             flow
!_______________________________________________________________________________
  subroutine  Initialize_vortexgreen_3dflow(ux, uy, uz, p, d)
    use parameters_constant_mod, only : HALF, ZERO, SIXTEEN, TWO
    use udf_type_mod
    use math_mod
    implicit none

    type(t_domain), intent(in   ) :: d
    real(WP),       intent(inout) :: ux(:, :, :), &
                                     uy(:, :, :), &
                                     uz(:, :, :), &
                                     p (:, :, :)

    real(WP) :: xc, yc, zc
    real(WP) :: xp, yp, zp
    integer(4) :: i, j, k

    do k = 1, d%nc(3)
      zc = d%h(3) * (real(k - 1, WP) + HALF)
      do j = 1, d%nc(2)
        yc = d%yc(j)
        do i = 1, d%np(1)
          xp = d%h(1) * real(i - 1, WP)
          ux(i, j, k) =  sin_wp ( xp ) * cos_wp ( yc ) * cos_wp ( zc )
        end do
      end do
    end do

    do k = 1, d%nc(3)
      zc = d%h(3) * (real(k - 1, WP) + HALF)
      do j = 1, d%np(2)
        yp = d%yp(j)
        do i = 1, d%nc(1)
          xc = d%h(1) * (real(i - 1, WP) + HALF)
          uy(i, j, k) = -cos_wp ( xc ) * sin_wp ( yp ) * cos_wp ( zc )
        end do
      end do
    end do

    do k = 1, d%np(3)
      do j = 1, d%nc(2)
        do i = 1, d%nc(1)
          uz(i, j, k) =  ZERO
        end do
      end do
    end do

    do k = 1, d%nc(3)
      zc = d%h(3) * (real(k - 1, WP) + HALF)
      do j = 1, d%nc(2)
        yc = d%yc(j)
        do i = 1, d%nc(1)
          xc = d%h(1) * (real(i - 1, WP) + HALF)
          p(i, j, k)= ( cos_wp( TWO * xc       ) + &
                        cos_wp( TWO * yc       ) ) * &
                      ( cos_wp( TWO * zc + TWO ) ) / SIXTEEN
        end do
      end do
    end do
    
    return
  end subroutine Initialize_vortexgreen_3dflow
!===============================================================================
!===============================================================================
!> \brief Initialize Sine signal for test only
!>
!> This subroutine is called locally once.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[in]     d             domain
!> \param[out]    f             flow
!_______________________________________________________________________________
  subroutine  Initialize_sinetest_flow(ux, uy, uz, p, d)
    use udf_type_mod, only : t_domain, t_flow
    use math_mod, only : sin_wp
    use parameters_constant_mod, only : HALF, ZERO, SIXTEEN, TWO
    
    implicit none

    type(t_domain), intent(in )   :: d
    real(WP),       intent(inout) :: ux(:, :, :), &
                                     uy(:, :, :), &
                                     uz(:, :, :), &
                                     p (:, :, :)

    real(WP) :: xc, yc, zc
    real(WP) :: xp, yp, zp
    integer(4) :: i, j, k

    do k = 1, d%nc(3)
      zc = d%h(3) * (real(k - 1, WP) + HALF)
      do j = 1, d%nc(2)
        yc = d%yc(j)
        do i = 1, d%np(1)
          xp = d%h(1) * real(i - 1, WP)
          ux(i, j, k) =  sin_wp ( xp ) + sin_wp(yc) + sin_wp(zc)
        end do 
      end do
    end do

    do k = 1, d%nc(3)
      zc = d%h(3) * (real(k - 1, WP) + HALF)
      do i = 1, d%nc(1)
        xc = d%h(1) * (real(i - 1, WP) + HALF)
        do j = 1, d%np(2)
          yp = d%yp(j)
          uy(i, j, k) = sin_wp ( xc ) + sin_wp(yp) + sin_wp(zc)
        end do
      end do
    end do

    
    do j = 1, d%nc(2)
      yc = d%yc(j)
      do i = 1, d%nc(1)
        xc = d%h(1) * (real(i - 1, WP) + HALF)
        do k = 1, d%np(3)
          zp = d%h(3) * real(k - 1, WP)
          uz(i, j, k) = sin_wp ( xc ) + sin_wp(yc) + sin_wp(zp)
        end do
      end do
    end do

    do j = 1, d%nc(2)
      yc = d%yc(j)
      do i = 1, d%nc(1)
        xc = d%h(1) * (real(i - 1, WP) + HALF)
        do k = 1, d%nc(3)
          zc = d%h(3) * (real(k - 1, WP) + HALF)
          p(i, j, k) = sin_wp ( xc ) + sin_wp(yc) + sin_wp(zc)
        end do
      end do
    end do
    
    return
  end subroutine Initialize_sinetest_flow

  subroutine  Initialize_burgers_flow(ux, uy, uz, p, d)
    use udf_type_mod, only : t_domain, t_flow
    use math_mod, only : sin_wp
    use parameters_constant_mod!, only : HALF, ZERO, SIXTEEN, TWO
    use input_general_mod
    implicit none

    type(t_domain), intent(in )   :: d
    real(WP),       intent(inout) :: ux(:, :, :), &
                                     uy(:, :, :), &
                                     uz(:, :, :), &
                                     p (:, :, :)

    real(WP) :: xc, yc, zc
    real(WP) :: xp, yp, zp
    integer(4) :: i, j, k
    real(WP),parameter :: alpha = ONE, beta = ZERO

    ux = ZERO
    uy = ZERO
    uz = ZERO
    p  = ZERO

 !===============================================================================
 ! example 1 : input sin(x)
 ! example 2 : input alpha * x + beta for inviscid Burgers' equation
 !===============================================================================
    if(icase == ICASE_HEATEQ .or. icase == ICASE_BURGERS) then
      do i = 1, d%np(idir)
        xp = d%h(idir) * real(i - 1, WP)
        if(idir == 1) ux(i, :, :) =  sin_wp ( PI * xp )
        if(idir == 2) uy(:, i, :) =  sin_wp ( PI * xp )
        if(idir == 3) uz(:, :, i) =  sin_wp ( PI * xp )
      end do 
    else if (icase == ICASE_INVSD_BURGERS) then
      do i = 1, d%np(idir)
        xp = d%h(idir) * real(i - 1, WP)
        if(idir == 1) ux(i, :, :) =  alpha * xp + beta
        if(idir == 2) uy(:, i, :) =  alpha * xp + beta
        if(idir == 3) uz(:, :, i) =  alpha * xp + beta
      end do 
    else
    end if
    
    return
  end subroutine Initialize_burgers_flow

  subroutine Check_maximum_velocity(ux, uy, uz)
    use precision_mod
    use math_mod
    implicit none

    real(WP), intent( in ) :: ux(:, :, :), uy(:, :, :), uz(:, :, :)

    real(WP)   :: u(3)
    integer(4) :: imax(3), jmax(3), kmax(3)

    u(1) = MAXVAL( abs_wp( ux(:, :, :) ) )
    u(2) = MAXVAL( abs_wp( uy(:, :, :) ) )
    u(3) = MAXVAL( abs_wp( uz(:, :, :) ) )

    imax = MAXLOC( abs_wp( ux(:, :, :) ) )
    jmax = MAXLOC( abs_wp( uy(:, :, :) ) )
    kmax = MAXLOC( abs_wp( uz(:, :, :) ) )

    Call Print_debug_mid_msg("  The maximum Ux, Uy, Uz are:")
    write(*, '(5X, A, 3I8.1, 1ES13.5)') 'Umax : ', imax, u(1)
    write(*, '(5X, A, 3I8.1, 1ES13.5)') 'Vmax : ', jmax, u(2)
    write(*, '(5X, A, 3I8.1, 1ES13.5)') 'Wmax : ', kmax, u(3)

    return
  end subroutine

!===============================================================================
!===============================================================================
!> \brief The main code for initializing flow variables
!>
!> This subroutine is called once in \ref Initialize_chapsim.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[inout]  none          NA
!_______________________________________________________________________________
  subroutine Initialize_flow_variables( domain, flow, thermo )
    use input_general_mod
    use parameters_constant_mod
    use boundary_conditions_mod
    use continuity_eq_mod
    use test_algrithms_mod
    use solver_tools_mod
    implicit none
    type(t_domain), intent(in   ) :: domain
    type(t_flow),   intent(inout) :: flow
    type(t_thermo), intent(inout) :: thermo

    logical :: itest = .false.

    interface 
       subroutine Display_vtk_slice(d, str, varnm, vartp, var0, iter)
        use udf_type_mod
        type(t_domain), intent( in ) :: d
        integer(4) :: vartp
        character( len = *), intent( in ) :: str
        character( len = *), intent( in ) :: varnm
        real(WP), intent( in ) :: var0(:, :, :)
        integer(4), intent( in ) :: iter
       end subroutine Display_vtk_slice
    end interface

    call Print_debug_start_msg("Initializing flow and thermal fields ...")
    call Calculate_RePrGr(flow, thermo, 0)
!-------------------------------------------------------------------------------
! to initialize thermal variables 
!-------------------------------------------------------------------------------
    call Print_debug_mid_msg("Initializing thermal field ...")
    if (ithermo == 1) then
      call Initialize_thermal_variables (flow, thermo)
    else
      flow%dDens(:, :, :) = ONE
      flow%mVisc(:, :, :) = ONE
    end if
!-------------------------------------------------------------------------------
! to initialize flow velocity and pressure
!-------------------------------------------------------------------------------
    call Print_debug_mid_msg("Initializing flow field ...")
    if ( (icase == ICASE_CHANNEL) .or. &
         (icase == ICASE_PIPE) .or. &
         (icase == ICASE_ANNUAL) ) then
      call Initialize_poiseuille_flow    (flow%qx, flow%qy, flow%qz, flow%pres, domain)
    else if (icase == ICASE_TGV2D) then
      call Initialize_vortexgreen_2dflow (flow%qx, flow%qy, flow%qz, flow%pres, domain)
    else if (icase == ICASE_TGV3D) then
      call Initialize_vortexgreen_3dflow (flow%qx, flow%qy, flow%qz, flow%pres, domain)
    else if (icase == ICASE_SINETEST) then
      call Initialize_sinetest_flow      (flow%qx, flow%qy, flow%qz, flow%pres, domain)
    else if(icase == ICASE_BURGERS .or. &
      icase == ICASE_INVSD_BURGERS .or. &
      icase == ICASE_HEATEQ) then
      call Initialize_burgers_flow       (flow%qx, flow%qy, flow%qz, flow%pres, domain)
    else
      call Print_error_msg("No such case defined" )
    end if
!-------------------------------------------------------------------------------
! to initialize pressure correction term
!-------------------------------------------------------------------------------
    flow%pcor(:, :, :) = ZERO
!-------------------------------------------------------------------------------
! to test algorithms based on given values.
!-------------------------------------------------------------------------------
    if(itest) call Test_schemes()
!-------------------------------------------------------------------------------
! to check maximum velocity
!-------------------------------------------------------------------------------
    call Check_maximum_velocity(flow%qx, flow%qy, flow%qz)
!-------------------------------------------------------------------------------
! to apply the b.c. 
!-------------------------------------------------------------------------------
    call Apply_BC_velocity (flow%qx, flow%qy, flow%qz, domain)
!-------------------------------------------------------------------------------
! to update mass flux terms 
!-------------------------------------------------------------------------------
    if (ithermo == 1) then
      call Calculate_massflux_from_velocity (flow, domain)
    else
      flow%gx(:, :, :) = flow%qx(:, :, :)
      flow%gy(:, :, :) = flow%qy(:, :, :)
      flow%gz(:, :, :) = flow%qz(:, :, :)
    end if
!-------------------------------------------------------------------------------
! to set up old arrays 
!-------------------------------------------------------------------------------
    flow%dDensm1(:, :, :) = flow%dDens(:, :, :)
    flow%dDensm2(:, :, :) = flow%dDens(:, :, :)
!-------------------------------------------------------------------------------
! to write and display the initial fields
!-------------------------------------------------------------------------------
    !call Display_vtk_slice(domain, 'xy', 'u', 1, qx)
    !call Display_vtk_slice(domain, 'xy', 'v', 2, qy)
    !call Display_vtk_slice(domain, 'xy', 'p', 0, pres)

    !call Display_vtk_slice(domain, 'yz', 'v', 2, qy)
    !call Display_vtk_slice(domain, 'yz', 'w', 3, qz)
    !call Display_vtk_slice(domain, 'yz', 'p', 0, pres)

    !call Display_vtk_slice(domain, 'zx', 'u', 1, qx)
    !call Display_vtk_slice(domain, 'zx', 'w', 3, qz)
    !call Display_vtk_slice(domain, 'zx', 'p', 0, pres)

    !call Display_vtk_slice(domain, 'xy', 'u', 1, flow%qx, 0)
    !call Display_vtk_slice(domain, 'xy', 'v', 2, flow%qy, 0)
    !call Display_vtk_slice(domain, 'xy', 'w', 0, flow%pres, 0)

    call Print_debug_end_msg
    return
  end subroutine
!===============================================================================
!===============================================================================
!> \brief The main code for initializing flow variables
!>
!> This subroutine is called once in \ref Initialize_chapsim.
!>
!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[inout]  
!_______________________________________________________________________________
  subroutine Calculate_RePrGr(f, t, iter)
    use input_general_mod
    use input_thermo_mod, only : tpRef0
    use parameters_constant_mod, only : GRAVITY, ONE
    use udf_type_mod, only : t_flow, t_thermo
    implicit none
    type(t_flow),   intent(inout) :: f
    type(t_thermo), intent(inout) :: t
    integer(4),     intent(in   ) :: iter  
  
    real(WP) :: u0
  
    if(iter < nIterIniRen) then
      f%rre = ONE / renIni
    else
      f%rre = ONE / ren
    end if
  
    if(ithermo == 1) then
  
      t%rPrRen = f%rre * tpRef0%k / tpRef0%m / tpRef0%cp
  
      u0 = ONE / f%rre * tpRef0%m / tpRef0%d / lenRef
      if (igravity == 0) then
        ! no gravity
        f%fgravity = ZERO
      else if (igravity == 1 .or. igravity == 2 .or. igravity == 3 ) then 
        ! flow/gravity same dirction
        f%fgravity =  lenRef / u0 / u0 * GRAVITY
      else if (igravity == -1 .or. igravity == -2 .or. igravity == -3 ) then 
        ! flow/gravity opposite dirction
        f%fgravity = -lenRef / u0 / u0 * GRAVITY
      else
        ! no gravity
        f%fgravity = ZERO
      end if
  
    end if
  
    return
  end subroutine Calculate_RePrGr

end module flow_variables_mod