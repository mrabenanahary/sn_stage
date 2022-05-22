!> Module containing all hydrodynamics
module mod_hd
  use mod_hd_phys
  use mod_hd_hllc
  use mod_hd_roe
  use mod_hd_ppm

  use mod_amrvac

  implicit none
  public

contains

  subroutine hd_activate()
    call hd_phys_init()
    call hd_hllc_init()
    call hd_roe_init()
    call hd_ppm_init()
  end subroutine hd_activate

  subroutine link_hd_pre_phys()
    use mod_hd_phys
    call hd_pre_read()
  end subroutine link_hd_pre_phys

end module mod_hd
