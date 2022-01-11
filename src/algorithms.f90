module tridiagonal_matrix_algorithm
  implicit none

  private :: Solve_TDMA_basic
  private :: Solve_TDMA_cyclic
  public  :: Preprocess_TDMA_coeffs
  public  :: Solve_TDMA

  public :: Test_TDMA_noncyclic
  public :: Test_TDMA_cyclic

contains

  subroutine Preprocess_TDMA_coeffs(a, b, c, d, n)
    use math_mod
    use parameters_constant_mod, only : ONE
    use precision_mod
    implicit none
    integer(4), intent(in) :: n
    real(WP), intent(in)    :: a(n), b(n)
    real(WP), intent(inout) :: c(n)
    real(WP), intent(out)   :: d(n)
    integer(4) :: i

    ! prepare coefficients
    c(1) = c(1) / b(1)
    
    do i = 2, n
      d(i) = ONE / ( b(i) - a(i) * c(i - 1) )
      if (i < n) c(i) = c(i) * d(i)
    end do

    return
  end subroutine Preprocess_TDMA_coeffs

  subroutine Solve_TDMA_basic(x, a, b, c, d, n)
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! solution of a tridiagnal system of n equations of the form
! 
!  a(i) * x(i-1) + b(i) * x(i) + c(i) * x(i+1) = R(i), i = 1, ..., n
!  a(1) and c(n) are not used. 
!  The solution x(i) is restored in R(i).
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    use precision_mod
    implicit none

    integer(4), intent(in) :: n
    real(WP), intent(inout) :: x(n) ! R in, X out.
    real(WP), intent(in) :: a(n), b(n)
    real(WP), intent(in) :: c(n), d(n)
    integer(4) :: i
    
    x(1) = x(1) / b(1)
    
    ! forward substitution
    do i = 2, n
      x(i) = ( x(i) - a(i) * x(i-1) ) * d(i)
    end do

    ! backward substitution
    do i = n-1, 1, -1
      x(i) = x(i) - c(i) * x(i+1)  
    end do

    return
  end subroutine Solve_TDMA_basic



  subroutine Solve_TDMA_cyclic(x, a, b, c, d, n)

    use precision_mod
    implicit none
    
    integer(4), intent(in) :: n
    real(WP), intent(inout) :: x(n) ! R in, X out.
    real(WP), intent(in) :: a(n), b(n)
    real(WP), intent(in) :: c(n), d(n)
    real(WP) :: x1(n)

    call Solve_TDMA_basic(x(1:n-1), a(1:n-1), b(1:n-1), c(1:n-1), d(1:n-1), n-1)
    
    x1(:) = 0.0
    x1(1) = - a(1)
    x1(n-1) =  - c(n-1)
    call Solve_TDMA_basic(x1(1:n-1), a(1:n-1), b(1:n-1), c(1:n-1), d(1:n-1), n-1)

    x(n) = (x(n) - c(n) * x(1) - a(n) * x(n-1)) / &
           (b(n) + c(n) * x1(1) + a(n) * x1(n-1))
    x(1:n-1) = x(1:n-1) + x1(1:n-1) * x(n)
    return
  end subroutine Solve_TDMA_cyclic

  subroutine Solve_TDMA(peri, x, a, b, c, d, n)
    use input_general_mod
    use precision_mod
    implicit none
    logical, intent(in) :: peri
    integer(4), intent(in) :: n
    real(WP), intent(inout) :: x(n) ! R in, X out.
    real(WP), intent(in) :: a(n), b(n)
    real(WP), intent(in) :: c(n), d(n)

    if(peri) then
      call Solve_TDMA_cyclic(x(:), a(:), b(:), c(:), d(:), n)
    else 
      call Solve_TDMA_basic (x(:), a(:), b(:), c(:), d(:), n)
    end if

    return
  end subroutine

  subroutine Test_TDMA_noncyclic
    use precision_mod
    implicit none
    integer(4), parameter :: n = 10
    real(WP) :: a(n), b(n), c(n), d(n), r(n)
    real(WP) :: ref(n)
    integer(4) :: i
    !real(WP) :: PI = 3.1416926

    ! example 1, n = 10
    a(1: n) = [3.0_WP, 1.0_WP, 1.0_WP, 7.0_WP, 6.0_WP, 3.0_WP, 8.0_WP, 6.0_WP, 5.0_WP, 4.0_WP]
    b(1: n) = [2.0_WP, 3.0_WP, 3.0_WP, 2.0_WP, 2.0_WP, 4.0_WP, 1.0_WP, 2.0_WP, 4.0_WP, 5.0_WP]
    c(1: n) = [1.0_WP, 2.0_WP, 1.0_WP, 6.0_WP, 1.0_WP, 3.0_WP, 5.0_WP, 7.0_WP, 3.0_WP, 5.0_WP]
    r(1: n) = [1.0_WP, 2.0_WP, 6.0_WP, 34.0_WP, 10.0_WP, 1.0_WP, 4.0_WP, 22.0_WP, 25.0_WP, 3.0_WP]
    ref=[1.0_WP, -1.0_WP, 2.0_WP, 1.0_WP, 3.0_WP, -2.0_WP, 0.0_WP, 4.0_WP, 2.0_WP, -1.0_WP]

    ! example 2, n = 7
    ! a(1 : n) = [2.0_WP, 1.0_WP/4.0_WP, 1.0_WP/3.0_WP, 1.0_WP/3.0_WP, 1.0_WP/3.0_WP, 1.0_WP/4.0_WP, 2.0_WP]
    ! b(1 : n) = [1.0_WP, 1.0_WP, 1.0_WP, 1.0_WP, 1.0_WP, 1.0_WP, 1.0_WP]
    ! c(1 : n) = [2.0_WP, 1.0_WP/4.0_WP, 1.0_WP/3.0_WP, 1.0_WP/3.0_WP, 1.0_WP/3.0_WP, 1.0_WP/4.0_WP, 2.0_WP]
    ! r(1 : n) = [2.06748E+00_WP,  6.20245E-01_WP, -6.66189E-01_WP, -1.33238E+00_WP, -6.66189E-01_WP,  &
    !             6.20245E-01_WP,  2.06748E+00_WP]
    ! ref(1: n) = [dcos(0.0_WP), dcos(PI/3.0_WP), dcos(2.0_WP*PI/3.0_WP), &
    !             dcos(PI), dcos(4.0_WP*PI/3.0_WP), dcos(5.0_WP*PI/3.0_WP), dcos(2.0_WP*PI)]

    d(:) = 0.0

    call Preprocess_TDMA_coeffs(a(:), b(:), c(:), d(:), n)
    !write(*,'(A,7F8.4)') 'a', a(:)
    !write(*,'(A,7F8.4)') 'b', b(:)
    !write(*,'(A,7F8.4)') 'c', c(:)
    !write(*,'(A,7F8.4)') 'd', d(:)
    !write(*,'(A,7F8.4)') 'r', r(:)

    call Solve_TDMA(.false., r(:), a(:), b(:), c(:), d(:), n)
    !write(*,'(A,7F8.4)') 'o', r(:)
    ! data output
    write(*, '(A)') 'Test_TDMA_noncyclic: cal, ref, diff'
    do i = 1, n
      write(*, '(I3, 2F8.4, 1ES15.7)') i, r(i), ref(i), dabs(r(i)-ref(i))
    end do
    
    return
  end subroutine Test_TDMA_noncyclic

  subroutine Test_TDMA_cyclic
    use precision_mod
    implicit none
    integer(4), parameter :: n = 10
    real(WP) :: a(n), b(n), c(n), d(n), r(n)
    real(WP) :: ref(n)
    integer(4) :: i

    a(1: n) = [3.0_WP, 1.0_WP, 1.0_WP, 7.0_WP, 6.0_WP, 3.0_WP, 8.0_WP, 6.0_WP, 5.0_WP, 4.0_WP]
    b(1: n) = [2.0_WP, 3.0_WP, 3.0_WP, 2.0_WP, 2.0_WP, 4.0_WP, 1.0_WP, 2.0_WP, 4.0_WP, 5.0_WP]
    c(1: n) = [1.0_WP, 2.0_WP, 1.0_WP, 6.0_WP, 1.0_WP, 3.0_WP, 5.0_WP, 7.0_WP, 3.0_WP, 5.0_WP]
    r(1: n) = [1.0_WP, 2.0_WP, 6.0_WP, 34.0_WP, 10.0_WP, 1.0_WP, 4.0_WP, 22.0_WP, 25.0_WP, 3.0_WP]

    d(:) = 0.0

    call Preprocess_TDMA_coeffs(a(1:n-1), b(1:n-1), c(1:n-1), d(1:n-1), n-1)
    call Solve_TDMA(.true., r(:), a(:), b(:), c(:), d(:), n)

    ! data output
    ref=[518663._WP/174746._WP, -299297._WP/174746._WP, 182180._WP/87373._WP, &
         5419._WP/3718._WP, 480243._WP/174746._WP, -370592._WP/87373._WP, 566251._WP/174746._WP, &
         1212441._WP/174746._WP, -76._WP/47._WP, -187761._WP/174746._WP]
    write(*, '(A)') 'Test_TDMA_cyclic: cal, ref, diff'
    do i = 1, n
      write(*, '(I3, 2F8.4, 1ES15.7)') i, r(i), ref(i), dabs(r(i)-ref(i))
    end do

    return
  end subroutine Test_TDMA_cyclic

end module tridiagonal_matrix_algorithm


