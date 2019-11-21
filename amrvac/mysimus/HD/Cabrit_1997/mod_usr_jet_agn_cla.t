module mod_usr
  use mod_hd, only : hd_activate
  use mod_dust
  use mod_physics
  use mod_global_parameters
  use mod_obj_global_parameters
  use mod_obj_mat
  use mod_obj_cloud
  use mod_obj_ism
  use mod_obj_sn_remnant
  use mod_obj_usr_unit
  use mod_obj_cla_jet
  implicit none
  save
  real(dp) :: theta, kx, ly, vc

  type usr_config
    logical           :: physunit_on
    logical           :: sn_on
    logical           :: ism_on
    logical           :: cloud_on
    logical           :: jet_agn_on
    logical           :: ism_list_diff
    logical           :: cloud_list_diff
    logical           :: reset_medium
    integer           :: cloud_number
    integer           :: ism_number
    integer           :: jet_agn_number
    integer           :: cloud_structure
    character(len=30) :: coordinate_system
    character(len=30) :: filename
    logical           :: cloud_profile_on
    logical           :: cloud_profile_density_on
    logical           :: cloud_profile_pressure_on
    logical           :: cloud_profile_velocity_on

    real(kind=dp)     :: density_dusttogas_maxlimit
    real(kind=dp)     :: density_dusttogas_minlimit
  end type usr_config
  type(usr_config)    :: usrconfig
  integer, parameter  :: n_dust_max = 20
  real(dp) :: SUM_MASS   = 0.0_dp
  real(dp) :: SUM_VOLUME = 0.0_dp


  type (ISM),allocatable,target      :: ism_surround(:)
  type (cloud),allocatable,target    :: cloud_medium(:)
  type (cla_jet),allocatable,target  :: jet_agn(:)
  type (ISM),target                  :: ism_default
  type (cloud),target                :: cloud_default
  type (cla_jet),target              :: jet_agn_default
  type (dust),target                 :: dust_ary
  type (dust),allocatable,target     :: the_dust_inuse(:)
  type (supernovae_remnant), target  :: sn_wdust

  !type(star) :: star_ms
  !type(star) :: sun

  type(usrphysical_unit) :: usr_physunit





contains
  subroutine usr_init
    ! .. local ..
    integer :: i_cloud,i_ism
    !-------------------------------------------
    ! configuration of procedures to be used in this project
    usr_set_parameters  => initglobaldata_usr
    usr_init_one_grid   => initonegrid_usr
    usr_special_bc      => specialbound_usr
    usr_aux_output      => specialvar_output
    usr_add_aux_names   => specialvarnames_output
    usr_source          => specialsource_usr
    usr_refine_grid     => specialrefine_usr
    usr_special_global  => usr_global_var
    usr_process_grid    => process_grid_usr
    usr_get_dt          => special_get_dt
    usr_internal_bc     => usr_special_internal_bc
    call usr_set_default_parameters



    call usr_physunit%set_default

    ! set default values for supernovae remnant configuration
    call sn_wdust%set_default

    ! set default values for ISMs configuration
    call ism_default%set_default


    ! set default values for clouds configuration
    call cloud_default%set_default

    ! set default values for clouds configuration
    call jet_agn_default%set_default

    call usr_params_read(par_files)



    ! complet all physical unit in use
    if(usrconfig%physunit_on) then
      physics_type='hd'
      call usr_physunit%set_complet(physics_type)
    end if
    call usr_physical_unit
    call set_coordinate_system(trim(usrconfig%coordinate_system))
    call hd_activate


    call usr_check_conflict


  end subroutine usr_init
  !------------------------------------------------------------------
  !> default usr parameters from a file
  subroutine usr_set_default_parameters
    !-------------------------------------
    usrconfig%physunit_on         = .false.
    usrconfig%sn_on               = .false.
    usrconfig%ism_on              = .false.
    usrconfig%cloud_on            = .false.
    usrconfig%jet_agn_on          = .false.
    usrconfig%cloud_number        = 1
    usrconfig%ism_number          = 1
    usrconfig%jet_agn_number      = 1
    usrconfig%ism_list_diff       = .false.
    usrconfig%cloud_list_diff     = .false.
    usrconfig%reset_medium        = .false.
    usrconfig%coordinate_system   = 'slab'
    usrconfig%cloud_structure     = 0
    usrconfig%filename            = 'mod_usr_jet_agn_cla.t'


    usrconfig%density_dusttogas_maxlimit  = 1.0d6
    usrconfig%density_dusttogas_minlimit  = 1.0d-6

    usrconfig%cloud_profile_density_on  = .false.
    usrconfig%cloud_profile_pressure_on = .false.
    usrconfig%cloud_profile_velocity_on = .false.
  end subroutine usr_set_default_parameters
  !------------------------------------------------------------------
  !> Read this module s parameters from a file
  subroutine usr_params_read(files)
    character(len=*), intent(in) :: files(:)
    ! .. local ..
    integer                      :: i_file,i_reason
    character(len=70)            :: error_message
    integer                      :: i_cloud,i_ism,i_jet_agn
    !-------------------------------------
    namelist /usr_list/ usrconfig
    !-------------------------------------

    error_message = 'At '//trim(usrconfig%filename)//'  in the procedure : usr_params_read'

    if(mype==0)write(*,*)'Reading usr_list'
    Loop_ifile : do i_file = 1, size(files)
       open(unitpar, file=trim(files(i_file)), status="old")
       read(unitpar, usr_list, iostat=i_reason)
       cond_ierror : if(i_reason>0)then
        write(*,*)' Error in reading the parameters file : ',trim(files(i_file))
        write(*,*)' Error at namelist: ', trim(usrconfig%filename)
        write(*,*)' The code stops now '
        call mpistop(trim(error_message))
       elseif(i_reason<0)then cond_ierror
        write(*,*)' Reache the end of the file  : ',trim(files(i_file))
        write(*,*)' Error at namelist: usr_list'
        write(*,*)' The code stops now '
        call mpistop(trim(error_message))
       else cond_ierror
        write(*,*)' End of reading of the usr_list'
       end if cond_ierror
       close(unitpar)
    end do Loop_ifile





    if(usrconfig%physunit_on)then
      call usr_physunit%read_parameters(usr_physunit%myconfig,files)
    else
      call usr_unit_read(files)
      call usr_physunit%set_to_one
    end if

    if(usrconfig%sn_on)call sn_wdust%read_parameters(sn_wdust%myconfig,files)

    if(usrconfig%ism_on)then
      allocate(ism_surround(0:usrconfig%ism_number-1))
      Loop_allism : do i_ism =0,usrconfig%ism_number-1

       ism_surround(i_ism)%myconfig        = ism_default%myconfig
       ism_surround(i_ism)%mydust%myconfig = ism_default%mydust%myconfig

       ism_surround(i_ism)%myconfig%myindice=i_ism
       call ism_surround(i_ism)%read_parameters(ism_surround(i_ism)%myconfig,files)
      end do Loop_allism
    end if

    if(usrconfig%cloud_on)then
      allocate(cloud_medium(0:usrconfig%cloud_number-1))
      Loop_allcloud : do i_cloud =0,usrconfig%cloud_number-1
       cloud_medium(i_cloud)%myconfig          = cloud_default%myconfig
       cloud_medium(i_cloud)%mydust%myconfig   = cloud_default%mydust%myconfig
       cloud_medium(i_cloud)%myconfig%myindice = i_cloud

       call cloud_medium(i_cloud)%read_parameters(files,cloud_medium(i_cloud)%myconfig)
      end do Loop_allcloud
    end if

    if(usrconfig%jet_agn_on)then
      allocate(jet_agn(0:usrconfig%jet_agn_number-1))
      Loop_alljetagn : do i_jet_agn =0,usrconfig%jet_agn_number-1
       jet_agn(i_jet_agn)%myconfig          = jet_agn_default%myconfig
       jet_agn(i_jet_agn)%mydust%myconfig   = jet_agn_default%mydust%myconfig
       jet_agn(i_jet_agn)%myconfig%myindice = i_jet_agn

       call jet_agn(i_jet_agn)%read_parameters(files,jet_agn(i_jet_agn)%myconfig)
     end do Loop_alljetagn
    end if
  end subroutine usr_params_read

  !> subroutine to clean memory at the end
  subroutine usr_clean_memory_final
    if(usrconfig%ism_on)then
      if(allocated(ism_surround))deallocate(ism_surround)
    end if
    if(usrconfig%cloud_on)then
      if(allocated(cloud_medium))deallocate(cloud_medium)
    end if
    if(allocated(the_dust_inuse))deallocate(the_dust_inuse)
  end subroutine usr_clean_memory_final

!-------------------------------------------------------------------
!> subroutine read unit used in the code
  subroutine usr_unit_read(files)
   implicit none
   character(len=*), intent(in) :: files(:)
   integer                      :: i_file

   namelist /usr_unit_list/ unit_length , unit_time,unit_velocity,          &
                      unit_density, unit_numberdensity,                     &
                      unit_pressure,unit_temperature


  if(mype==0)write(*,*)'Reading usr_unit_list'
  Loop_read_usrfile : do i_file = 1, size(files)
         open(unitpar, file=trim(files(i_file)), status="old")
         read(unitpar, usr_unit_list, end=109)
  109    close(unitpar)
  end do Loop_read_usrfile
 end subroutine usr_unit_read
  !-----------------------------------------------------------
  !> subroutine to check configuration conflits
  subroutine usr_check_conflict
    implicit none
    ! .. local ..
    integer  :: i_ism,i_cloud,i_jet_agn
    !------------------------------
    cond_dust_on : if(.not.phys_config%dust_on)then
      if(usrconfig%ism_on)then
       Loop_isms : do i_ism=0,usrconfig%ism_number-1
        ism_surround(i_ism)%myconfig%dust_on =.false.
       end do Loop_isms
      end if
      if(usrconfig%cloud_on)then
       Loop_clouds : do i_cloud=0,usrconfig%cloud_number-1
        cloud_medium(i_cloud)%myconfig%dust_on =.false.
       end do Loop_clouds
      end if
      if(usrconfig%jet_agn_on)then
       Loop_jet_agn : do i_jet_agn=0,usrconfig%jet_agn_number-1
        jet_agn(i_jet_agn)%myconfig%dust_on =.false.
      end do Loop_jet_agn
      end if

      if(usrconfig%sn_on)then
        sn_wdust%myconfig%dust_on =.false.
      end if
    end if  cond_dust_on

    usrconfig%cloud_profile_on=usrconfig%cloud_profile_density_on   .or.&
                               usrconfig%cloud_profile_pressure_on  .or.&
                               usrconfig%cloud_profile_velocity_on

  end   subroutine usr_check_conflict
  !-----------------------------------------------------------
  !> subroutine to normalize parameters in the code
  subroutine usr_normalise_parameters
   implicit none
   integer            :: idust



   constusr%G         = constusr%G*&
                      (unit_density*(unit_length/unit_velocity)**(2.0_dp))


   constusr%clight                      = constusr%clight/unit_velocity

   ! complet all physical unit in use
   if(usrconfig%physunit_on) then
      call usr_physunit%fillphysunit
    end if


    w_convert_factor(phys_ind%rho_)                       = unit_density
    if(phys_config%energy)w_convert_factor(phys_ind%e_)   = unit_density*unit_velocity**2.0
    if(saveprim)then
     w_convert_factor(phys_ind%mom(:))                    = unit_velocity
    else
     w_convert_factor(phys_ind%mom(:))                    = unit_density*unit_velocity
    end if
    time_convert_factor                                   = unit_time
    length_convert_factor                                 = unit_length




    if(phys_config%dust_on)then
          w_convert_factor(phys_ind%dust_rho(:))              = unit_density
          if(saveprim)then
            do idust = 1, phys_config%dust_n_species
             w_convert_factor(phys_ind%dust_mom(:,idust))     = unit_velocity
            end do
          else
            do idust = 1, phys_config%dust_n_species
             w_convert_factor(phys_ind%dust_mom(:,idust))     = unit_density*unit_velocity
           end do
          end if
    end if

  end subroutine usr_normalise_parameters


!-------------------------------------------------------------------------
  subroutine initglobaldata_usr
   use mod_variables
   implicit none
   ! .. local ..
   integer   :: i_cloud,i_ism,i_jet_agn,n_objects,n_object_w_dust
   !------------------------------------
    n_objects       = 0
    n_object_w_dust = 0
    itr=1
   ! complet ism parameters
   if(usrconfig%ism_on)then
    Loop_isms : do i_ism=0,usrconfig%ism_number-1
     ism_surround(i_ism)%myconfig%itr=itr
     call ism_surround(i_ism)%set_complet
     call ism_surround(i_ism)%normalize(usr_physunit)
     if(ism_surround(i_ism)%myconfig%dust_on)n_object_w_dust=n_object_w_dust+1
    end do Loop_isms
    itr=ism_surround(usrconfig%ism_number-1)%myconfig%itr+1
    n_objects = n_objects + usrconfig%ism_number
   end if



   ! complet cloud parameters
   cond_cloud_on : if(usrconfig%cloud_on) then
     Loop_clouds : do i_cloud=0,usrconfig%cloud_number-1
      cloud_medium(i_cloud)%myconfig%itr=itr
      call cloud_medium(i_cloud)%set_complet
      call cloud_medium(i_cloud)%normalize(usr_physunit)
      if(cloud_medium(i_cloud)%myconfig%dust_on)n_object_w_dust=n_object_w_dust+1
     end do Loop_clouds
     itr=cloud_medium(usrconfig%cloud_number-1)%myconfig%itr+1
     n_objects = n_objects + usrconfig%cloud_number
   end if cond_cloud_on


   ! complet jet parameters
   if(usrconfig%jet_agn_on) then
     Loop_jet_agn : do i_jet_agn=0,usrconfig%jet_agn_number-1
      jet_agn(i_jet_agn)%myconfig%itr=itr
      jet_agn(i_jet_agn)%myconfig%pressure_associate_ism = ism_surround(0)%myconfig%pressure &
                                                           *usr_physunit%myconfig%pressure
      call jet_agn(i_jet_agn)%set_complet
      call jet_agn(i_jet_agn)%normalize(usr_physunit)
      if(jet_agn(i_jet_agn)%myconfig%dust_on)n_object_w_dust=n_object_w_dust+1
     end do Loop_jet_agn
     itr=jet_agn(usrconfig%jet_agn_number-1)%myconfig%itr+1
     n_objects = n_objects + usrconfig%jet_agn_number
   end if

   if(usrconfig%sn_on)then
     sn_wdust%myconfig%itr=itr
     call sn_wdust%set_complet
     call sn_wdust%normalize(usr_physunit)
     itr=sn_wdust%myconfig%itr+1
     n_objects = n_objects + 1
     if(sn_wdust%myconfig%dust_on)n_object_w_dust=n_object_w_dust+1
   end if

   if(phys_config%dust_on)allocate(the_dust_inuse(n_object_w_dust))

   call usr_normalise_parameters
   if(mype==0)call usr_write_setting

  end subroutine initglobaldata_usr
  !> The initial conditions
  subroutine initonegrid_usr(ixI^L,ixO^L,w,x)
    ! initialize one grid

    implicit none

    integer, intent(in)     :: ixI^L,ixO^L
    real(dp), intent(in)    :: x(ixI^S,1:ndim)
    real(dp), intent(inout) :: w(ixI^S,1:nw)
    !.. local ..
    real(dp)      :: res
    integer       :: ix^D,na,flag(ixI^S)
    integer       :: i_cloud,i_ism,i_jet_agn,i_dust,i_start,i_end
    logical, save :: first=.true.
    logical       :: patch_all(ixI^S)
    logical       :: patch_inuse(ixI^S)
    type(dust)    :: dust_dummy
    integer       :: i_object_w_dust
    real(dp)      :: cloud_profile(ixI^S,1:nw)
    ! .. only test ..
    real(dp)      ::old_w(ixO^S,1:nw)
    !-----------------------------------------
    patch_all(ixO^S) = .true.
    if(first)then
      if(mype==0) then
        write(*,*)'Jet start :-)'
      endif
      first=.false.
    endif

    i_object_w_dust=0
    ! set the ism
    cond_ism_on : if(usrconfig%ism_on) then
      Loop_isms : do i_ism=0,usrconfig%ism_number-1
       ism_surround(i_ism)%subname='initonegrid_usr'
       call ism_surround(i_ism)%set_w(ixI^L,ixO^L,global_time,x,w)
       patch_all(ixO^S) =  patch_all(ixO^S) .and. .not.ism_surround(i_ism)%patch(ixO^S)
       if(ism_surround(i_ism)%myconfig%dust_on)then
         i_object_w_dust = i_object_w_dust +1
         if(.not.allocated(the_dust_inuse(i_object_w_dust)%patch))allocate(the_dust_inuse(i_object_w_dust)%patch(ixI^S))
         the_dust_inuse(i_object_w_dust)%myconfig    = ism_surround(i_ism)%mydust%myconfig
         if(.not.allocated(the_dust_inuse(i_object_w_dust)%the_ispecies))&
         allocate(the_dust_inuse(i_object_w_dust)%the_ispecies&
                   (the_dust_inuse(i_object_w_dust)%myconfig%idust_first:&
                    the_dust_inuse(i_object_w_dust)%myconfig%idust_last))
         the_dust_inuse(i_object_w_dust)%patch(ixO^S)=ism_surround(i_ism)%mydust%patch(ixO^S)
       end if
      end do Loop_isms
    end if cond_ism_on




    ! set jet agn
    cond_jet_on : if(usrconfig%jet_agn_on)then
      Loop_jet_agn : do i_jet_agn=0,usrconfig%jet_agn_number-1
       jet_agn(i_jet_agn)%subname='initonegrid_usr'
       call jet_agn(i_jet_agn)%set_w(ixI^L,ixO^L,global_time,x,w)
       patch_inuse(ixO^S) = jet_agn(i_jet_agn)%patch(ixO^S)
       cond_ism_onjet : if(usrconfig%ism_on)then
        Loop_isms2 : do i_ism=0,usrconfig%ism_number-1
          if(ism_surround(i_ism)%myconfig%tracer_on)then
           where(patch_inuse(ixO^S))
             w(ixO^S,phys_ind%tracer(ism_surround(i_ism)%myconfig%itr))=0.0_dp
           end where
          end if


          cond_ism_dust_onjet : if(ism_surround(i_ism)%myconfig%dust_on) then
            ism_surround(i_ism)%mydust%patch(ixO^S)=.not.patch_inuse(ixO^S)
            i_start= ism_surround(i_ism)%mydust%myconfig%idust_first
            i_end  = ism_surround(i_ism)%mydust%myconfig%idust_last
            Loop_ism_idustjet :  do i_dust=i_start,i_end
              ism_surround(i_ism)%mydust%the_ispecies(i_dust)%patch(ixO^S)=&
                                           .not.patch_inuse(ixO^S)
            end do Loop_ism_idustjet
          call ism_surround(i_ism)%mydust%set_w_zero(ixI^L,ixO^L,x,w)
          end if cond_ism_dust_onjet
        end do Loop_isms2
       end if cond_ism_onjet

       patch_all(ixO^S) =  patch_all(ixO^S) .and. .not.patch_inuse(ixO^S)
       if(jet_agn(i_jet_agn)%myconfig%dust_on)then
         i_object_w_dust = i_object_w_dust +1
         if(.not.allocated(the_dust_inuse(i_object_w_dust)%patch))allocate(the_dust_inuse(i_object_w_dust)%patch(ixI^S))
         the_dust_inuse(i_object_w_dust)%myconfig    = jet_agn(i_jet_agn)%mydust%myconfig
         if(.not.allocated(the_dust_inuse(i_object_w_dust)%the_ispecies))&
         allocate(the_dust_inuse(i_object_w_dust)%the_ispecies&
                   (the_dust_inuse(i_object_w_dust)%myconfig%idust_first:&
                    the_dust_inuse(i_object_w_dust)%myconfig%idust_last))
         the_dust_inuse(i_object_w_dust)%patch(ixO^S)= jet_agn(i_jet_agn)%patch(ixO^S)
       end if
     end do Loop_jet_agn
    end if cond_jet_on


    ! set one cloud
    cloud_on : if(usrconfig%cloud_on)then

      Loop_clouds : do i_cloud=0,usrconfig%cloud_number-1
       cloud_medium(i_cloud)%subname='initonegrid_usr'
       if(allocated(cloud_medium(i_cloud)%patch))deallocate(cloud_medium(i_cloud)%patch)
       allocate(cloud_medium(i_cloud)%patch(ixI^S))
       cloud_medium(i_cloud)%patch(ixO^S) = x(ixO^S,2)>cloud_medium(i_cloud)%myconfig%extend(2) +&
                                dtan(cloud_medium(i_cloud)%myconfig%extend(3)*&
                                     usr_physunit%myconfig%length*dpi/180.0_dp)*(x(ixO^S,1)-xprobmin1)


       cond_cloud_profile_on : if(usrconfig%cloud_profile_on)then
        call usr_set_profile_cloud(ixI^L,ixO^L,x,cloud_medium(i_cloud),cloud_profile)
       else cond_cloud_profile_on
        cloud_profile      = 1.0_dp
       end if cond_cloud_profile_on

       call cloud_medium(i_cloud)%set_w(ixI^L,ixO^L,global_time,x,w,&
                        usr_density_profile=cloud_profile(ixI^S,phys_ind%rho_),&
                        usr_pressure_profile=cloud_profile(ixI^S,phys_ind%pressure_),&
                        usr_velocity_profile=cloud_profile(ixI^S,phys_ind%mom(1):phys_ind%mom(ndir)))

       patch_inuse(ixO^S) = cloud_medium(i_cloud)%patch(ixO^S)
       ism_is_oncld : if(usrconfig%ism_on)then
        Loop_isms_cloud0 : do i_ism=0,usrconfig%ism_number-1
          cond_ism_tracer_oncld : if(ism_surround(i_ism)%myconfig%tracer_on)then
            where(patch_inuse(ixO^S))
             w(ixO^S,phys_ind%tracer(ism_surround(i_ism)%myconfig%itr))=0.0_dp
            end where
          end if cond_ism_tracer_oncld
          cond_ism_dust_oncld : if(ism_surround(i_ism)%myconfig%dust_on) then
            ism_surround(i_ism)%mydust%patch(ixO^S)=.not.patch_inuse(ixO^S)
            i_start= ism_surround(i_ism)%mydust%myconfig%idust_first
            i_end  = ism_surround(i_ism)%mydust%myconfig%idust_last
            Loop_ism_idustcld:  do i_dust=i_start,i_end
              ism_surround(i_ism)%mydust%the_ispecies(i_dust)%patch(ixO^S)=&
                                           .not.patch_inuse(ixO^S)
            end do Loop_ism_idustcld
            call ism_surround(i_ism)%mydust%set_w_zero(ixI^L,ixO^L,x,w)
          end if cond_ism_dust_oncld
        end do Loop_isms_cloud0
       end if ism_is_oncld

       jet_is_on : if(usrconfig%jet_agn_on)then
        Loop_jet_agn_clean : do i_jet_agn=0,usrconfig%jet_agn_number-1
         if(jet_agn(i_jet_agn)%myconfig%tracer_on)then

           where(patch_inuse(ixO^S))
             w(ixO^S,phys_ind%tracer(jet_agn(i_jet_agn)%myconfig%itr))=0.0_dp
           end where
         end if
        end do Loop_jet_agn_clean
       end if jet_is_on
       patch_all(ixO^S) =  patch_all(ixO^S) .and. .not.patch_inuse(ixO^S)
       if(cloud_medium(i_cloud)%myconfig%dust_on)then
         i_object_w_dust = i_object_w_dust +1
         if(.not.allocated(the_dust_inuse(i_object_w_dust)%patch))allocate(the_dust_inuse(i_object_w_dust)%patch(ixI^S))
         the_dust_inuse(i_object_w_dust)%myconfig     = cloud_medium(i_cloud)%mydust%myconfig
         if(.not.allocated(the_dust_inuse(i_object_w_dust)%the_ispecies))&
         allocate(the_dust_inuse(i_object_w_dust)%the_ispecies&
         (the_dust_inuse(i_object_w_dust)%myconfig%idust_first:&
          the_dust_inuse(i_object_w_dust)%myconfig%idust_last))
         call the_dust_inuse(i_object_w_dust)%set_patch(ixI^L,ixO^L, cloud_medium(i_cloud)%patch)
      !   the_dust_inuse(i_object_w_dust)%patch(ixO^S) = cloud_medium(i_cloud)%patch(ixO^S)
       end if
      end do Loop_clouds
    end if cloud_on

    ! set the pulsar and associated wind + envelope if they are on
    cond_sn_on : if(usrconfig%sn_on)then
      sn_wdust%subname='initonegrid_usr'
      call sn_wdust%set_w(ixI^L,ixO^L,global_time,x,w)
      patch_inuse(ixO^S) =  sn_wdust%patch(ixO^S)
      cond_ism_onsn : if(usrconfig%ism_on)then
       Loop_isms_sn : do i_ism=0,usrconfig%ism_number-1
        cond_ism_tracer_sn : if(ism_surround(i_ism)%myconfig%tracer_on)then
          where(patch_inuse(ixO^S))
            w(ixO^S,phys_ind%tracer(ism_surround(0)%myconfig%itr))=0.0_dp
          endwhere
        end if cond_ism_tracer_sn
        cond_ism_dust_sn : if(ism_surround(i_ism)%myconfig%dust_on) then
          ism_surround(i_ism)%mydust%patch(ixO^S)=.not.patch_inuse(ixO^S)
          i_start= ism_surround(i_ism)%mydust%myconfig%idust_first
          i_end  = ism_surround(i_ism)%mydust%myconfig%idust_last
          Loop_ism_idustsn:  do i_dust=i_start,i_end
            ism_surround(i_ism)%mydust%the_ispecies(i_dust)%patch(ixO^S)=&
                                                  .not.patch_inuse(ixO^S)
          end do Loop_ism_idustsn
          call ism_surround(i_ism)%mydust%set_w_zero(ixI^L,ixO^L,x,w)
        end if cond_ism_dust_sn
       end do   Loop_isms_sn
      end if cond_ism_onsn

      patch_all(ixO^S) =  patch_all(ixO^S) .and. .not.patch_inuse(ixO^S)
      cond_sn_dust : if(sn_wdust%myconfig%dust_on)then
        i_object_w_dust  = i_object_w_dust + 1
        if(.not.allocated(the_dust_inuse(i_object_w_dust)%patch))allocate(the_dust_inuse(i_object_w_dust)%patch(ixI^S))
        the_dust_inuse(i_object_w_dust)%myconfig    = sn_wdust%mydust%myconfig
        the_dust_inuse(i_object_w_dust)%patch(ixO^S)=sn_wdust%patch(ixO^S)
      end if cond_sn_dust
    end if cond_sn_on



    if(any(patch_all(ixO^S)))then
      call usr_fill_empty_region(ixI^L,ixO^L,0.0_dp,patch_all,x,w)
    end if


  ! put dust to zero in all other zones
    cond_dust_on : if(phys_config%dust_on) then
      dust_dummy%myconfig%idust_first = 1
      dust_dummy%myconfig%idust_last  = phys_config%dust_n_species
      call dust_dummy%set_allpatch(ixI^L,ixO^L,the_dust_inuse)
      call dust_dummy%set_w_zero(ixI^L,ixO^L,x,w)
      call dust_dummy%clean_memory
      if(allocated(the_dust_inuse(i_object_w_dust)%patch))deallocate(the_dust_inuse(i_object_w_dust)%patch)
    end if cond_dust_on

    ! check is if initial setting is correct
    call  phys_check_w(.true., ixI^L, ixO^L, w, flag)

    if(any(flag(ixO^S)>0)) PRINT*,' is error',maxval(flag(ixO^S)),minval(w(ixO^S,phys_ind%pressure_))


    ! get conserved variables to be used in the code
    call phys_to_conserved(ixI^L,ixO^L,w,x)

    call usr_clean_memory


  end subroutine initonegrid_usr
  !============================================================================
  subroutine specialsource_usr(qdt,ixI^L,ixO^L,iw^LIM,qtC,wCT,qt,w,x)
    use mod_dust
    implicit none

    integer, intent(in)             :: ixI^L, ixO^L, iw^LIM
    real(dp), intent(in)            :: qdt, qtC, qt
    real(dp), intent(in)            :: wCT(ixI^S,1:nw), x(ixI^S,1:ndim)
    real(dp), intent(inout)         :: w(ixI^S,1:nw)
    ! .. local ..
    integer                         :: i_cloud,i_ism,i_jet_agn
    logical, dimension(ixI^S)       :: escape_patch
    real(kind=dp), dimension(ixI^S) :: source_filter,density_ratio
    real(kind=dp)                   :: usr_loc_tracer_small_density
    real(dp)                        :: coef_correct
    integer                         :: idir,idust,ix^D,ixL^D,ixR^L
    integer                         :: patch_back_cloud(ixI^S)

    !----------------------------------------------------------
!return
    cond_reset : if(usrconfig%reset_medium) then
     escape_patch(ixO^S) =.false.
     cond_jet_on : if(usrconfig%jet_agn_on)then
       Loop_jet_agn : do i_jet_agn=0,usrconfig%jet_agn_number-1
         cond_jet_tracer_on : if(jet_agn(i_jet_agn)%myconfig%tracer_on)  then
          jet_agn(i_jet_agn)%subname='specialsource_usr'
          call jet_agn(i_jet_agn)%alloc_set_patch(ixI^L,ixO^L,qt,x,use_tracer=.false.,w=w)
          escape_patch(ixO^S) =  escape_patch(ixO^S).or.jet_agn(i_jet_agn)%patch(ixO^S)
          if(any(x(ixO^S,2)>jet_agn(i_jet_agn)%myconfig%z_impos))then
            usr_loc_tracer_small_density = jet_agn(i_jet_agn)%myconfig%tracer_small_density/10.0_dp
          else
            usr_loc_tracer_small_density = jet_agn(i_jet_agn)%myconfig%tracer_small_density
          end if
          escape_patch(ixO^S) =  escape_patch(ixO^S).or.&
             w(ixO^S,phys_ind%tracer(jet_agn(i_jet_agn)%myconfig%itr))&
             >usr_loc_tracer_small_density

          where(w(ixO^S,phys_ind%tracer(jet_agn(i_jet_agn)%myconfig%itr))<&
                    usr_loc_tracer_small_density)
            w(ixO^S,phys_ind%tracer(jet_agn(i_jet_agn)%myconfig%itr)) = 0.0_dp
          end where
          !escape_patch(ixO^S) = escape_patch(ixO^S).or. &
          !                      (x(ixO^S,x_)>1.1*jet_agn(i_jet_agn)%myconfig%r_in_init.and.&
          !                      x(ixO^S,x_)<1.1*jet_agn(i_jet_agn)%myconfig%r_out_impos)


        end if cond_jet_tracer_on

       end do Loop_jet_agn

     end if cond_jet_on
     ! set one cloud
     cond_usr_cloud : if(usrconfig%cloud_on)then
      Loop_clouds : do i_cloud=0,usrconfig%cloud_number-1
       cond_cloud_tracer : if(cloud_medium(i_cloud)%myconfig%tracer_on)  then
        cloud_medium(i_cloud)%subname='specialsource_usr'
        if(allocated(cloud_medium(i_cloud)%patch))deallocate(cloud_medium(i_cloud)%patch)
        call cloud_medium(i_cloud)%alloc_set_patch(ixI^L,ixO^L,qt,x,use_tracer=.true.,w=w)
        escape_patch(ixO^S) =  escape_patch(ixO^S).or.cloud_medium(i_cloud)%patch(ixO^S)
       end if cond_cloud_tracer
      end do Loop_clouds
     end if cond_usr_cloud


     ! add force in ISM
     cond_ism_on : if(usrconfig%ism_on) then
        Loop_isms0 : do i_ism=0,usrconfig%ism_number-1
         where(w(ixO^S,phys_ind%rho_)<min(ism_surround(i_ism)%myconfig%density,&
                                          minval(jet_agn(:)%myconfig%density))/10.0_dp)
           escape_patch(ixO^S)=.false.
         elsewhere(w(ixO^S,phys_ind%rho_)>ism_surround(i_ism)%myconfig%density.and.&
            w(ixO^S,phys_ind%tracer(ism_surround(i_ism)%myconfig%itr))>5.0d3.and.&
            x(ixO^S,2)>2.0*maxval(jet_agn(:)%myconfig%z_impos))
            escape_patch(ixO^S)=.true.
         end where
        end do Loop_isms0
        if(.not.(all(escape_patch(ixO^S))))then
          Loop_isms : do i_ism=0,usrconfig%ism_number-1
            source_filter(ixO^S) = 0.5_dp*(1.0_dp-tanh((x(ixO^S,2))&
                               /(2.0_dp*maxval(jet_agn(:)%myconfig%z_impos))))&
                              *(w(ixO^S,phys_ind%tracer(ism_surround(i_ism)%myconfig%itr))&
                              /max(w(ixO^S,phys_ind%tracer(ism_surround(i_ism)%myconfig%itr))+&
                               w(ixO^S,phys_ind%tracer(jet_agn(0)%myconfig%itr)),smalldouble ) )

            cond_tracer_ism_on : if(ism_surround(i_ism)%myconfig%reset_on &
                                   .and.ism_surround(i_ism)%myconfig%tracer_on)then
              where(.not.escape_patch(ixO^S))w(ixO^S,phys_ind%tracer(ism_surround(i_ism)%myconfig%itr))=1.0d3
              call ism_surround(i_ism)%add_source(ixI^L,ixO^L,iw^LIM,x,qdt,qtC,&
                                                  wCT,qt,w,use_tracer=.true.,&
                                                  escape_patch=escape_patch,&
                                                  source_filter=source_filter)
            end if cond_tracer_ism_on
          end do  Loop_isms
        end if
      end if cond_ism_on

     call usr_clean_memory
    end if cond_reset


    coef_correct   = 0.4_dp
    Loop_idust : do idust =1, phys_config%dust_n_species
      density_ratio(ixO^S)=w(ixO^S, phys_ind%dust_rho(idust))/w(ixO^S, phys_ind%rho_)

     Loop_idir2 : do idir = 1,ndir

     where(density_ratio(ixO^S)>smalldouble.and.&
          ((density_ratio(ixO^S)<usrconfig%density_dusttogas_minlimit.or.density_ratio(ixO^S)>usrconfig%density_dusttogas_maxlimit).or.&
        (w(ixO^S, phys_ind%dust_mom(idir,idust))*w(ixO^S,phys_ind%mom(idir))<0.0_dp)))
       w(ixO^S, phys_ind%dust_mom(idir,idust)) = w(ixO^S,phys_ind%mom(idir))*&
                                                 density_ratio(ixO^S)

!       w(ixO^S, phys_ind%dust_mom(idir,idust))=(1.0_dp-coef_correct)&
!            *w(ixO^S, phys_ind%dust_mom(idir,idust))&
!            +coef_correct*w(ixO^S,phys_ind%mom(idir))

     end where
      where(density_ratio(ixO^S)>usrconfig%density_dusttogas_maxlimit)
        w(ixO^S, phys_ind%dust_rho(idust)) = &
          usrconfig%density_dusttogas_maxlimit*w(ixO^S, phys_ind%rho_)
        w(ixO^S, phys_ind%dust_mom(idir,idust)) = w(ixO^S,phys_ind%mom(idir))*&
                              usrconfig%density_dusttogas_maxlimit
      elsewhere(density_ratio(ixO^S)<usrconfig%density_dusttogas_minlimit**2.0_dp)
        w(ixO^S, phys_ind%dust_rho(idust)) = 0.0_dp
        w(ixO^S, phys_ind%dust_mom(idir,idust)) =  0.0_dp
      end where
     end do Loop_idir2
    end do Loop_idust

  end subroutine specialsource_usr
  !========================================================================
  subroutine process_grid_usr(igrid,level,ixI^L,ixO^L,qt,w,x)
    use mod_global_parameters
    implicit none
    integer, intent(in)             :: igrid,level,ixI^L,ixO^L
    real(kind=dp)   , intent(in)    :: qt,x(ixI^S,1:ndim)
    real(kind=dp)   , intent(inout) :: w(ixI^S,1:nw)

    ! .. local ..
    integer                         :: idust,idir
    real(dp)                        :: small_dust_rho,coef
    logical, dimension(ixI^S)       :: patch_correct,patch_slow
    integer       :: i_cloud,i_ism,i_jet_agn,i_dust,i_start,i_end
    logical, save :: first=.true.
    logical       :: patch_all(ixI^S)
    integer       :: i_object
    !---------------------------------------------------




    cond_usr_cloud : if(usrconfig%cloud_on)then
     Loop_clouds : do i_cloud=0,usrconfig%cloud_number-1
      cond_cloud_on : if(cloud_medium(i_cloud)%myconfig%time_cloud_on>0.0_dp.and.&
                            dabs(cloud_medium(i_cloud)%myconfig%time_cloud_on-qt)<smalldouble)  then

       cloud_medium(i_cloud)%subname='process_grid_usr'
       if(allocated(cloud_medium(i_cloud)%patch))deallocate(cloud_medium(i_cloud)%patch)
       allocate(cloud_medium(i_cloud)%patch(ixI^S))
       cloud_medium(i_cloud)%patch(ixO^S) = x(ixO^S,2)>cloud_medium(i_cloud)%myconfig%extend(2) +&
                                dtan(cloud_medium(i_cloud)%myconfig%extend(3)*&
                                     usr_physunit%myconfig%length*dpi/180.0_dp)*(x(ixO^S,1)-xprobmin1)
       call cloud_medium(i_cloud)%set_w(ixI^L,ixO^L,global_time,x,w)

       ism_is_on2 : if(usrconfig%ism_on)then
         if(ism_surround(0)%myconfig%tracer_on)then
           where(cloud_medium(i_cloud)%patch(ixO^S))
             w(ixO^S,phys_ind%tracer(ism_surround(0)%myconfig%itr))=0.0_dp
           end where
         end if
       end if ism_is_on2

       jet_is_on : if(usrconfig%jet_agn_on)then
        Loop_jet_agn_clean : do i_jet_agn=0,usrconfig%jet_agn_number-1
         if(jet_agn(i_jet_agn)%myconfig%tracer_on)then
           where(cloud_medium(i_cloud)%patch(ixO^S))
             w(ixO^S,phys_ind%tracer(jet_agn(0)%myconfig%itr))=0.0_dp
           end where
         end if
        end do Loop_jet_agn_clean
       end if jet_is_on

       patch_all(ixO^S) =  patch_all(ixO^S) .and. .not.cloud_medium(i_cloud)%patch(ixO^S)
       if(cloud_medium(i_cloud)%myconfig%dust_on)the_dust_inuse(i_object)=cloud_medium(i_cloud)%mydust
       i_object = i_object +1
     end if cond_cloud_on
    end do Loop_clouds
    end if cond_usr_cloud

    if(phys_config%dust_on) then
     small_dust_rho = sn_wdust%mydust%myconfig%min_limit_rel

     call phys_to_primitive(ixI^L,ixI^L,w,x)
     ! handel small density dust
     Loop_idust : do idust =1, dust_n_species
      where(w(ixI^S, phys_ind%dust_rho(idust))<max(small_dust_rho*w(ixI^S,phys_ind%rho_),&
         ism_surround(0)%mydust%myconfig%min_limit_abs))
        w(ixI^S, phys_ind%dust_rho(idust))= 0.8* min(small_dust_rho*w(ixI^S,phys_ind%rho_),&
             ism_surround(0)%mydust%myconfig%min_limit_abs)
        patch_correct(ixI^S) = .true.
      elsewhere
        patch_correct(ixI^S) = .false.
      end where
      ! handel large density dust
      where(w(ixI^S,phys_ind%rho_)<0.9*ism_surround(0)%myconfig%density)
       where(w(ixI^S, phys_ind%dust_rho(idust))>ism_surround(0)%mydust%myconfig%max_limit_rel*w(ixI^S,phys_ind%rho_))
        w(ixI^S, phys_ind%dust_rho(idust))=0.8*ism_surround(0)%mydust%myconfig%max_limit_rel*w(ixI^S,phys_ind%rho_)
        patch_slow(ixI^S) = .true.
       elsewhere
        patch_slow(ixI^S) =.false.
       end where
      end where
      ! handel large cmax in rarefied region
      ! do idir = 1, ndim
      !   call phys_get_cmax(w,x,ixI^L,ixO^L,idir,cmax)
      !
      ! end do


    !  new_dvflag(ixI^S)=.true.
    !  new_dfflag(ixI^S)=.true.

    !  vt2(ixI^S) = 3.0d0*w(ixI^S,e_)/w(ixI^S, rho_)
      Loop_idir1 : do idir = 1,ndim
       where(patch_correct(ixI^S))
        w(ixI^S, phys_ind%dust_mom(idir,idust))=0.0_dp
       end where
       where(patch_slow(ixI^S))
               w(ixI^S, phys_ind%dust_mom(idir,idust))=w(ixI^S,phys_ind%mom(idir))
       end where
      end do   Loop_idir1
     end do Loop_idust
     call phys_to_conserved(ixI^L,ixI^L,w,x)
    end if

  end subroutine process_grid_usr
  !---------------------------------------------------------------------
  !-------------------------------------------------------------------------
  subroutine specialbound_usr(qt,ixI^L,ixO^L,iB,w,x)
    ! special boundary types, user defined
    integer, intent(in)     :: ixO^L, iB, ixI^L
    real(dp), intent(in)    :: qt, x(ixI^S,1:ndim)
    real(dp), intent(inout) :: w(ixI^S,1:nw)
    ! .. local ..
    integer                 :: flag(ixI^S)
    integer                 :: i_cloud,i_ism,i_jet_agn
    integer                 :: i_object_w_dust
    integer                 :: idims,iside
    integer                 :: i_start,i_end,i_dust
    logical                 :: patch_all(ixI^S),patch_inuse(ixI^S)
    real(dp)                :: cloud_profile(ixI^S,1:nw)
    !-------------------------------------

    patch_all(ixO^S) = .true.
    i_object_w_dust = 1
    idims = ceiling(real(iB,kind=dp)/2.0_dp)
    iside = iB-2*(idims-1)

  ! set the ism
    cond_ism_on: if(usrconfig%ism_on)then
     Loop_isms : do i_ism=0,usrconfig%ism_number-1
      ism_surround(i_ism)%subname='specialbound_usr'
      call ism_surround(i_ism)%set_w(ixI^L,ixO^L,qt,x,w,isboundary_iB=(/idims,iside/))
      patch_all(ixO^S) =  patch_all(ixO^S) .and.(.not.ism_surround(i_ism)%patch(ixO^S))
      if(ism_surround(i_ism)%myconfig%dust_on)the_dust_inuse(i_object_w_dust)=ism_surround(i_ism)%mydust
      i_object_w_dust = i_object_w_dust +1
     end do Loop_isms
   end if cond_ism_on
  ! set one cloud
    cond_cloud_on : if(usrconfig%cloud_on)then
     Loop_clouds : do i_cloud=0,usrconfig%cloud_number-1
      cloud_medium(i_cloud)%subname='specialbound_usr'
      if(allocated(cloud_medium(i_cloud)%patch))deallocate(cloud_medium(i_cloud)%patch)
      allocate(cloud_medium(i_cloud)%patch(ixI^S))
      cloud_medium(i_cloud)%patch(ixO^S) = x(ixO^S,2)>cloud_medium(i_cloud)%myconfig%extend(2) +&
                                dtan(cloud_medium(i_cloud)%myconfig%extend(3)*&
                                     usr_physunit%myconfig%length*dpi/180.0_dp)*(x(ixO^S,1)-xprobmin1)

       if(usrconfig%cloud_profile_on)then
        call usr_set_profile_cloud(ixI^L,ixO^L,x,cloud_medium(i_cloud),cloud_profile)
       else
        cloud_profile      = 1.0_dp
       end if

       call cloud_medium(i_cloud)%set_w(ixI^L,ixO^L,global_time,x,w)!,&
                        usr_density_profile=cloud_profile(ixI^S,phys_ind%rho_),&
                        usr_pressure_profile=cloud_profile(ixI^S,phys_ind%pressure_),&
                        usr_velocity_profile=cloud_profile(ixI^S,phys_ind%mom(1):phys_ind%mom(ndir)))

       patch_inuse(ixO^S) = cloud_medium(i_cloud)%patch(ixO^S)
       ism_is_oncld : if(usrconfig%ism_on)then
        Loop_isms_cloud0 : do i_ism=0,usrconfig%ism_number-1
          cond_ism_tracer_oncld : if(ism_surround(i_ism)%myconfig%tracer_on)then
            where(patch_inuse(ixO^S))
             w(ixO^S,phys_ind%tracer(ism_surround(i_ism)%myconfig%itr))=0.0_dp
            end where
          end if cond_ism_tracer_oncld
          cond_ism_dust_oncld : if(ism_surround(i_ism)%myconfig%dust_on) then
            ism_surround(i_ism)%mydust%patch(ixO^S)=.not.patch_inuse(ixO^S)
            i_start= ism_surround(i_ism)%mydust%myconfig%idust_first
            i_end  = ism_surround(i_ism)%mydust%myconfig%idust_last
            Loop_ism_idustcld:  do i_dust=i_start,i_end
              ism_surround(i_ism)%mydust%the_ispecies(i_dust)%patch(ixO^S)=&
                                           .not.patch_inuse(ixO^S)
            end do Loop_ism_idustcld
            call ism_surround(i_ism)%mydust%set_w_zero(ixI^L,ixO^L,x,w)
          end if cond_ism_dust_oncld
        end do Loop_isms_cloud0
       end if ism_is_oncld

       jet_is_on : if(usrconfig%jet_agn_on)then
        Loop_jet_agn_clean : do i_jet_agn=0,usrconfig%jet_agn_number-1
         if(jet_agn(i_jet_agn)%myconfig%tracer_on)then
           where(patch_inuse(ixO^S))
             w(ixO^S,phys_ind%tracer(jet_agn(i_jet_agn)%myconfig%itr))=0.0_dp
           end where
         end if
        end do Loop_jet_agn_clean
       end if jet_is_on
     end do Loop_clouds
   end if  cond_cloud_on

  ! set jet
    cond_agn_on : if(usrconfig%jet_agn_on)then
     Loop_jet_agn : do i_jet_agn=0,usrconfig%jet_agn_number-1
      jet_agn(i_jet_agn)%subname='specialbound_usr'
      call jet_agn(i_jet_agn)%set_w(ixI^L,ixO^L,qt,x,w)
       patch_inuse(ixO^S) = jet_agn(i_jet_agn)%patch(ixO^S)
       cond_ism_onjet : if(usrconfig%ism_on)then
        Loop_ism_jet : do i_ism=0,usrconfig%ism_number-1
          if(ism_surround(i_ism)%myconfig%tracer_on)then
           where(patch_inuse(ixO^S))
             w(ixO^S,phys_ind%tracer(ism_surround(i_ism)%myconfig%itr))=0.0_dp
           end where
          end if


          cond_ism_dust_onjet : if(ism_surround(i_ism)%myconfig%dust_on) then
            ism_surround(i_ism)%mydust%patch(ixO^S)=.not.patch_inuse(ixO^S)
            i_start= ism_surround(i_ism)%mydust%myconfig%idust_first
            i_end  = ism_surround(i_ism)%mydust%myconfig%idust_last
            Loop_ism_idustjet :  do i_dust=i_start,i_end
              ism_surround(i_ism)%mydust%the_ispecies(i_dust)%patch(ixO^S)=&
                                           .not.patch_inuse(ixO^S)
            end do Loop_ism_idustjet
            call ism_surround(i_ism)%mydust%set_w_zero(ixI^L,ixO^L,x,w)
          end if cond_ism_dust_onjet
        end do Loop_ism_jet
       end if cond_ism_onjet

       patch_all(ixO^S) =  patch_all(ixO^S) .and. .not.patch_inuse(ixO^S)
       if(jet_agn(i_jet_agn)%myconfig%dust_on)then
         the_dust_inuse(i_object_w_dust)=jet_agn(i_jet_agn)%mydust
         i_object_w_dust = i_object_w_dust +1
       end if
     end do Loop_jet_agn
    end if cond_agn_on


    if(any(patch_all(ixO^S)))then
     call usr_fill_empty_region(ixI^L,ixO^L,qt,patch_all,x,w)
    end if


  ! get conserved variables to be used in the code

  call phys_to_conserved(ixI^L,ixO^L,w,x)


  call usr_clean_memory


  end subroutine specialbound_usr


!----------------------------------------------------------------
  subroutine usr_clean_memory
    implicit none
    ! .. local ..
    integer   :: i_cloud,i_ism,i_jet_agn
    !------------------------------
        if(usrconfig%ism_on)then
          Loop_isms : do i_ism=0,usrconfig%ism_number-1
           call ism_surround(i_ism)%clean_memory
          end do Loop_isms
        end if
        if(usrconfig%cloud_on)then
          Loop_clouds : do i_cloud=0,usrconfig%cloud_number-1
           call cloud_medium(i_cloud)%clean_memory
          end do Loop_clouds
        end if

        if(usrconfig%jet_agn_on)then
          Loop_jet_agn : do i_jet_agn=0,usrconfig%jet_agn_number-1
           jet_agn(i_jet_agn)%subname='usr_clean_memory'
           call jet_agn(i_jet_agn)%clean_memory
         end do Loop_jet_agn
        end if

        if(usrconfig%sn_on)then
           call sn_wdust%clean_memory
        end if
  end subroutine usr_clean_memory


     !> Enforce additional refinement or coarsening
     !> One can use the coordinate info in x and/or time qt=t_n and w(t_n) values w.
     !> you must set consistent values for integers refine/coarsen:
     !> refine = -1 enforce to not refine
     !> refine =  0 doesn't enforce anything
     !> refine =  1 enforce refinement
     !> coarsen = -1 enforce to not coarsen
     !> coarsen =  0 doesn't enforce anything
     !> coarsen =  1 enforce coarsen
     !> e.g. refine for negative first coordinate x < 0 as
     !> if (any(x(ix^S,1) < zero)) refine=1
     subroutine specialrefine_usr(igrid,level,ixI^L,ixO^L,qt,w,x,refine,coarsen)
       use mod_global_parameters
       integer, intent(in)          :: igrid, level, ixI^L, ixO^L
       real(dp), intent(in)         :: qt, w(ixI^S,1:nw), x(ixI^S,1:ndim)
       integer, intent(inout)       :: refine, coarsen
       ! .. local ..
       integer                      :: level_min,level_max,level_need
       logical                      :: patch_cond
       real(dp)                     :: dx_loc(1:ndim)
       integer                      :: i_jet_agn
      !----------------------------------------

      Loop_jet_agn : do i_jet_agn=0,usrconfig%jet_agn_number-1
       cond_init_jet: if(dabs(qt-jet_agn(i_jet_agn)%myconfig%time_cla_jet_on)&
                        <smalldouble) then
        jet_agn(i_jet_agn)%subname='specialrefine_usr'
        ^D&dx_loc(^D)=rnode(rpdx^D_,igrid);
        call jet_agn(i_jet_agn)%set_patch(ixI^L,ixO^L,qt,x,&
                                          force_refine=1,dx_loc=dx_loc)

        if(any(jet_agn(i_jet_agn)%patch(ixO^S)))then
         level_need= nint(dlog((dabs(jet_agn(i_jet_agn)%myconfig%r_out_init&
                                  -jet_agn(i_jet_agn)%myconfig%r_in_init))&
                           /domain_nx1)/dlog(2.0_dp))
         level_min = max(jet_agn(i_jet_agn)%myconfig%refine_min_level&
                         ,level_need)
         level_max = jet_agn(i_jet_agn)%myconfig%refine_max_level
         patch_cond=.true.
         call user_fixrefineregion(level,level_min,level_max,&
                                   patch_cond,refine,coarsen)
         else
         refine =-1
         coarsen= 1
        end if
        call jet_agn(i_jet_agn)%clean_memory
       end if cond_init_jet
      end do Loop_jet_agn
      ! supernovae_remnant
      cond_init_t: if(dabs(qt-0.0_dp)<smalldouble) then
        ^D&dx_loc(^D)=rnode(rpdx^D_,igrid);
        cond_sn_on : if(usrconfig%sn_on) then
          call sn_wdust%get_patch(ixI^L,ixO^L,qt,x,force_refine=1,dx_loc=dx_loc)
          if(any(sn_wdust%patch(ixO^S)))then
           level_need = nint(dlog((xprobmax1/sn_wdust%myconfig%r_out)/domain_nx1)/dlog(2.0_dp))
           level_min = level_need+1
           level_max = refine_max_level
           patch_cond=.true.
           call user_fixrefineregion(level,level_min,level_max,patch_cond,refine,coarsen)
          else
           refine  = -1
           coarsen = 1
          end if
          call sn_wdust%clean_memory
        end if cond_sn_on
      end if cond_init_t

      ! if(qt<wn_pulsar%myconfig%t_end_pulsar_wind.and.&
      !    qt<wn_pulsar%myconfig%t_start_pulsar_wind)return
      ! cond_pulsar_on : if(usrconfig%pulsar_on)then
      !
      ! end if cond_pulsar_on
     end subroutine specialrefine_usr
  !=====================================================================
     subroutine user_fixrefineregion(level,level_min,level_max,patch_cond,refine,coarsen)
     integer, intent(in)    :: level,level_min,level_max
     logical,intent(in)     :: patch_cond
     integer, intent(inout) :: refine, coarsen
     ! .. local ..
     !-------------------------------------------
     if(patch_cond)then
      if(level>level_max)then
        coarsen = 1
        refine  = -1
      else if(level==level_max)then
        coarsen = 0
        refine  = -1
      end if
      if(level<level_min)then
        coarsen = -1
        refine  =  1
      else if(level==level_min)then
        coarsen = -1
        refine  =  0
      end if
     end if
     end subroutine user_fixrefineregion

     subroutine special_get_dt(w,ixI^L,ixO^L,qt,dtnew,dx^D,x)
       use mod_global_parameters
       integer, intent(in)             :: ixI^L, ixO^L
       double precision, intent(in)    :: dx^D,qt, x(ixI^S,1:ndim)
       double precision, intent(in)    :: w(ixI^S,1:nw)
       double precision, intent(inout) :: dtnew
       ! .. local ...
       integer                         :: i_cloud
       !--------------------------------------------------------------
        cond_usr_cloud : if(usrconfig%cloud_on)then
          Loop_clouds : do i_cloud=0,usrconfig%cloud_number-1
            cond_cloud_on : if(cloud_medium(i_cloud)%myconfig%time_cloud_on>0.0_dp.and.&
                              cloud_medium(i_cloud)%myconfig%time_cloud_on>qt)  then
              dtnew= cloud_medium(i_cloud)%myconfig%time_cloud_on-qt
            end if   cond_cloud_on
          end do Loop_clouds
        end if cond_usr_cloud

     end subroutine special_get_dt
   !> This subroutine can be used to artificially overwrite ALL conservative
   !> variables in a user-selected region of the mesh, and thereby act as
   !> an internal boundary region. It is called just before external (ghost cell)
   !> boundary regions will be set by the BC selection. Here, you could e.g.
   !> want to introduce an extra variable (nwextra, to be distinguished from nwaux)
   !> which can be used to identify the internal boundary region location.
   !> Its effect should always be local as it acts on the mesh.
   subroutine usr_special_internal_bc(level,qt,ixI^L,ixO^L,w,x)
     use mod_global_parameters
     integer, intent(in)             :: ixI^L,ixO^L,level
     real(kind=dp)   , intent(in)    :: qt
     real(kind=dp)   , intent(inout) :: w(ixI^S,1:nw)
     real(kind=dp)   , intent(in)    :: x(ixI^S,1:ndim)
     ! .. local ..
     integer                         :: i_jet_agn
     !--------------------------------------------------------------
    cond_jet_on : if(usrconfig%jet_agn_on)then

      Loop_jet_agn : do i_jet_agn=0,usrconfig%jet_agn_number-1
        cond_jet_start : if(qt>jet_agn(i_jet_agn)%myconfig%time_cla_jet_on)then
         cond_jet_impose : if(jet_agn(i_jet_agn)%myconfig%z_impos>xprobmin2)then
          call jet_agn(i_jet_agn)%set_patch(ixI^L,ixO^L,qt,x)
          cond_insid_jet : if(any(jet_agn(i_jet_agn)%patch(ixO^S)))then
            call phys_to_primitive(ixI^L,ixO^L,w,x)
            call jet_agn(i_jet_agn)%set_w(ixI^L,ixO^L,qt,x,w)
            ! get conserved variables to be used in the code
            call phys_to_conserved(ixI^L,ixO^L,w,x)
          end if cond_insid_jet
          call usr_clean_memory
         end if cond_jet_impose
        end if cond_jet_start
      end do Loop_jet_agn

    end if cond_jet_on
   end subroutine usr_special_internal_bc
  !> special output
  subroutine specialvar_output(ixI^L,ixO^L,win,x,normconv)
  ! this subroutine can be used in convert, to add auxiliary variables to the
  ! converted output file, for further analysis using tecplot, paraview, ....
  ! these auxiliary values need to be stored in the nw+1:nw+nwauxio slots
  ! the array normconv can be filled in the (nw+1:nw+nwauxio) range with
  ! corresponding normalization values (default value 1)
    use mod_physics
    use mod_dust
    implicit none
    integer, intent(in)        :: ixI^L,ixO^L
    real(dp), intent(in)       :: x(ixI^S,1:ndim)
    real(dp)                   :: win(ixI^S,nw+nwauxio)
    real(dp)                   :: normconv(0:nw+nwauxio)
    ! .. local ..
    real(dp)                   :: w(ixI^S,nw)
    real(dp)                   :: error_var(ixM^T)
    integer                    :: iw, level,idir,idust
    integer, parameter         :: imach_             = 1
    integer, parameter         :: itemperature_      = 2
    integer, parameter         :: ilevel_            = 3
    integer, parameter         :: indensity_         = 4
    integer, parameter         :: ierror_lohner_rho_ = 5
    integer, parameter         :: ierror_lohner_p_   = 6
    integer, parameter         :: ideltav_dust11_    = 7
    integer, parameter         :: ideltav_dust12_    = 8
    integer, parameter         :: irhod1torho_       = 9

    real(dp),dimension(ixI^S)                                  :: csound2,temperature
    real(dp),dimension(ixI^S,ndir)                             :: vgas
    real(dp),dimension(ixI^S,ndir,phys_config%dust_n_species)  :: vdust

    !----------------------------------------------------
    w(ixI^S,1:nw) = win(ixI^S,1:nw)
    level = node(plevel_,saveigrid)


    Loop_iw :  do iw = 1,nwauxio
    select case(iw)
    case(imach_)
      call phys_get_csound2(w,x,ixI^L,ixO^L,csound2)
      win(ixO^S,nw+imach_) = dsqrt(SUM(w(ixO^S,phys_ind%mom(1):phys_ind%mom(ndir))**2.0_dp&
                                ,dim=ndim+1)/csound2(ixO^S))&
                                /(w(ixO^S,phys_ind%rho_))
      case(itemperature_)
        call phys_get_temperature( ixI^L, ixO^L,w, x, temperature)
        win(ixO^S,nw+itemperature_) = temperature(ixO^S)*unit_temperature
        normconv(nw+itemperature_)  = 1.0_dp
      case(ilevel_)
        normconv(nw+ilevel_)     = 1.0_dp
        win(ixO^S,nw+ilevel_) = node(plevel_,saveigrid)

      case(indensity_)
        normconv(nw+indensity_)     = 1.0_dp
        win(ixO^S,nw+indensity_)    = w(ixO^S,phys_ind%rho_)*unit_density/mp_cgs
      case(ierror_lohner_rho_)
        normconv(nw+iw)     = 1.0_dp
        win(ixG^T,nw+ierror_lohner_rho_) = 0.0
        call usr_mat_get_Lohner_error(ixI^L, ixM^LL,level,phys_ind%rho_,w,error_var)
        win(ixM^T,nw+ierror_lohner_rho_) = error_var(ixM^T)
      case(ierror_lohner_p_)
        normconv(nw+iw)     = 1.0_dp
        win(ixG^T,nw+ierror_lohner_p_) = 0.0_dp
        call usr_mat_get_Lohner_error(ixI^L, ixM^LL,level,phys_ind%pressure_,w,error_var)
        win(ixM^T,nw+ierror_lohner_p_) = error_var(ixM^T)

      case(ideltav_dust11_)
        normconv(nw+iw)     = 1.0_dp
        dust_on_deltav11 : if(phys_config%dust_on)then
            idir=1
            vgas(ixI^S,idir)=w(ixI^S,phys_ind%mom(idir))/w(ixI^S,phys_ind%rho_)
            idust = 1
            where(w(ixI^S,phys_ind%dust_rho(idust))>phys_config%dust_small_density)
              vdust(ixI^S,idir,idust)=w(ixI^S,phys_ind%dust_mom(idir, idust))&
                                  /w(ixI^S,phys_ind%dust_rho(idust))
              win(ixI^S,nw+ideltav_dust11_) = vgas(ixI^S,idir)  - vdust(ixI^S,idir,idust)
            elsewhere
              vdust(ixI^S,idir,idust)       = 0.0_dp
              win(ixI^S,nw+ideltav_dust11_) = 0.0_dp
            endwhere
        end if  dust_on_deltav11

      case(ideltav_dust12_)
        normconv(nw+iw)     = 1.0_dp
        dust_on_deltav12 : if(phys_config%dust_on)then
            idir=2
            vgas(ixI^S,idir)=w(ixI^S,phys_ind%mom(idir))/w(ixI^S,phys_ind%rho_)
            idust = 1
            where(w(ixI^S,phys_ind%dust_rho(idust))>phys_config%dust_small_density)
              vdust(ixI^S,idir,idust)=w(ixI^S,phys_ind%dust_mom(idir, idust))&
                                  /w(ixI^S,phys_ind%dust_rho(idust))
              win(ixI^S,nw+ideltav_dust12_) = vgas(ixI^S,idir)  - vdust(ixI^S,idir,idust)

            elsewhere
              vdust(ixI^S,idir,idust)       = 0.0_dp
              win(ixI^S,nw+ideltav_dust12_) = 0.0_dp
            endwhere
        end if  dust_on_deltav12
      case(irhod1torho_)
        normconv(nw+iw)     = 1.0_dp
        idust = 1
        where(w(ixI^S,phys_ind%dust_rho(idust))>phys_config%dust_small_density)
          win(ixI^S,nw+irhod1torho_) = w(ixI^S,phys_ind%dust_rho(idust)) /&
                                          w(ixI^S,phys_ind%rho_)
        elsewhere
          win(ixI^S,nw+irhod1torho_) = 0.0_dp
        end where
      case default
       write(*,*)'is not implimented at specialvar_output in mod_user'
    end select
  end do Loop_iw
    !----------------------------------------------------

   !w(ixI^S,1:nw)=win(ixI^S,1:nw)


  end subroutine specialvar_output


  !> this subroutine is ONLY to be used for computing auxiliary variables
  !> which happen to be non-local (like div v), and are in no way used for
  !> flux computations. As auxiliaries, they are also not advanced

  subroutine specialvarnames_output(varnames)
  ! newly added variables need to be concatenated with the w_names/primnames string
    character(len=*), intent(inout) :: varnames(:)
    ! .. local ..
    integer                    :: iw
    integer, parameter         :: imach_             = 1
    integer, parameter         :: itemperature_      = 2
    integer, parameter         :: ilevel_            = 3
    integer, parameter         :: indensity_         = 4
    integer, parameter         :: ierror_lohner_rho_ = 5
    integer, parameter         :: ierror_lohner_p_   = 6
    integer, parameter         :: ideltav_dust11_    = 7
    integer, parameter         :: ideltav_dust12_    = 8
    integer, parameter         :: irhod1torho_       = 9
    !----------------------------------------------------
    Loop_iw : do  iw = 1,nwauxio
      select case(iw)
      case(imach_)
        varnames(imach_)               = 'mach_number'
      case(itemperature_)
        varnames(itemperature_)        ='temperature'
      case(ilevel_)
        varnames(ilevel_)              = 'level'
      case(indensity_)
        varnames(indensity_)           = 'number density'
      case(ierror_lohner_rho_)
        varnames(ierror_lohner_rho_)   = 'erroramrrho'
      case(ierror_lohner_p_)
        varnames(ierror_lohner_p_)     = 'erroamrp'
      case(ideltav_dust11_)
        varnames(ideltav_dust11_)      = 'deltav_dust11'
      case(ideltav_dust12_)
        varnames(ideltav_dust12_)      = 'deltav_dust12'
      case(irhod1torho_)
        varnames(irhod1torho_)         = 'rhod1torho'
      end select
    end do Loop_iw



  end subroutine specialvarnames_output
  !---------------------------------------------------------------------
  !> subroutine to fill the space regions that are not filled by the model
  subroutine usr_fill_empty_region(ixI^L,ixO^L,qt,patchw_empty,x,w)
    use mod_global_parameters
    implicit none
    integer, intent(in)         :: ixI^L,ixO^L
    real(kind=dp), intent(in)   :: qt
    logical, intent(in)         :: patchw_empty(ixI^S)
    real(kind=dp),intent(in)    :: x(ixI^S,1:ndir)
    real(kind=dp),intent(inout) :: w(ixI^S,1:nw)
    ! .. local ..
    integer                     :: idir
    !------------------------------------------------
    where(patchw_empty(ixO^S))
      w(ixO^S,phys_ind%rho_)      = 1.0_DP
      w(ixO^S,phys_ind%pressure_)        = 1.0d-2
    end where
    Loop_idir_v : do idir=1,ndir
     where(patchw_empty(ixO^S))
      w(ixO^S,phys_ind%mom(idir)) = 0.0_dp
     end where
     if(phys_config%ismhd) then
        where(patchw_empty(ixO^S))
          w(ixO^S,phys_ind%mag(idir)) = 0.0_dp
        end where
      end if
    end do Loop_idir_v
  end subroutine usr_fill_empty_region

!---------------------------------------------------------------------
  !> Initialize the method and limiter
  subroutine special_reset_solver(ixI^L,ixO^L,qt,w,x,old_method,old_limiter,usr_method,usr_limiter)
    use mod_global_parameters
    use mod_limiter
    integer, intent(in)             :: ixI^L, ixO^L
    real(kind=dp), intent(in)       :: qt
    double precision, intent(in)    :: x(ixI^S,1:ndim)
    double precision, intent(in)    :: w(ixI^S,1:nw)
    character(len=*),intent(in)     :: old_method
    integer, intent(in)             :: old_limiter
    character(len=20),intent(inout) :: usr_method
    integer, intent(inout)          :: usr_limiter
    ! .. local ..
    real(kind=dp), dimension(ixO^S) :: theta
    real(kind=dp)                   :: theta_min
    !------------------------------------------------------
    return;
    theta_min=5.0_dp*dpi/180.0_dp
    usr_method  = old_method
    usr_limiter = old_limiter
    cond_pw : if(any(w(ixO^S,lfac_)>2.0_dp))then
     usr_method  = 'tvdlf'
     usr_limiter = limiter_minmod
    end if cond_pw
   {^NOONED
    where(x(ixO^S,z_)>smalldouble)
      theta(ixO^S) = atan(x(ixO^S,r_)/x(ixO^S,z_))
    elsewhere
      theta(ixO^S) = 0.0_dp
    end where
    cond_axis : if(any(theta(ixO^S)<20))then
      usr_method  = 'tvdlf'
      usr_limiter = old_limiter
    end if cond_axis
   }
  end subroutine special_reset_solver
  !---------------------------------------------------------------------
  !> subroutine to write simulation configuration
  subroutine usr_write_setting
    implicit none
    integer,parameter   :: unit_config =12
    character(len=75)   :: filename_config
    integer             :: i_cloud,i_ism,i_jet_agn
    !-------------------------------------
    filename_config=trim(base_filename)//'.config'

    open(unit_config,file=trim(filename_config), status='replace')
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%% Simulation configuration %%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    if(usrconfig%physunit_on)call usr_physunit%write_setting(unit_config)
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    if(usrconfig%sn_on)call sn_wdust%write_setting(unit_config)
    if(usrconfig%ism_on)then
      Loop_isms : do i_ism=0,usrconfig%ism_number-1
       call ism_surround(i_ism)%write_setting(unit_config)
      end do Loop_isms
    end if
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    if(usrconfig%cloud_on)then
      Loop_clouds : do i_cloud=0,usrconfig%cloud_number-1
       call cloud_medium(i_cloud)%write_setting(unit_config)
      end do Loop_clouds
    end if
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'


    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    if(usrconfig%jet_agn_on)then
      Loop_jet_agn : do i_jet_agn=0,usrconfig%jet_agn_number-1
       call jet_agn(i_jet_agn)%write_setting(unit_config)
      end do Loop_jet_agn
    end if
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    write(unit_config,*)'%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    close(unit_config)

  end subroutine usr_write_setting

!----------------------------------------------------------------------
!> compute the total mass and volume in the cloud
subroutine usr_global_var
  use mod_global_parameters

end subroutine usr_global_var
!-------------------------------------------------------------------------------------------
subroutine usr_set_profile_cloud(ixI^L,ixO^L,x,cloud_isuse,cloud_profile)

  use mod_global_parameters
  implicit none
  integer, intent(in)          :: ixI^L,ixO^L
  real(kind=dp), intent(in)    :: x(ixI^S,1:ndim)
  type(cloud), intent(in)      :: cloud_isuse
  real(kind=dp), intent(inout) :: cloud_profile(ixI^S,1:nw)
  ! .. local ..
  real(kind=dp)                :: fprofile(ixI^S),distance(ixI^S)
  real(kind=dp)                :: standart_deviation,angle_theta
  character(len=20)            :: profile
  integer                      :: idir
  !------------------------------------------------------------
  cloud_profile=1.0_dp

  angle_theta = cloud_isuse%myconfig%extend(3)*&
                          usr_physunit%myconfig%length*dpi/180.0_dp
  distance(ixO^S) =   (x(ixO^S,2)-&
                      ( dtan(angle_theta)*(x(ixO^S,1)-xprobmin1))+&
                        cloud_isuse%myconfig%extend(2))*dsin(angle_theta)

  select case(usrconfig%cloud_structure)
  case(1)
   profile='tanh'
   standart_deviation = cloud_isuse%myconfig%extend(2)
  case(2)
   profile='linear'
   standart_deviation = 2.0_dp*cloud_isuse%myconfig%extend(2)
  case default
   profile='none'
   standart_deviation = cloud_isuse%myconfig%extend(2)
  end select


  call usr_mat_profile_dist(ixI^L,ixO^L,profile, distance,&
                            standart_deviation,fprofile)

  select case(usrconfig%cloud_structure)
  case(1)
    where(distance(ixO^S)>cloud_isuse%myconfig%extend(2))
      fprofile(ixO^S) = 10.0_dp * fprofile(ixO^S)
    end where
  case(2)
    where(distance(ixO^S)>cloud_isuse%myconfig%extend(2))
      fprofile(ixO^S) = 10.0_dp !* fprofile(ixO^S)
    end where

  case default
    fprofile = 1.0_dp
  end select

  if(usrconfig%cloud_profile_density_on)then
    where(cloud_isuse%patch(ixO^S))
     cloud_profile(ixO^S,phys_ind%rho_) = fprofile(ixO^S)
    end where
  else
    where(cloud_isuse%patch(ixO^S))
      cloud_profile(ixO^S,phys_ind%rho_) = 1.0_dp
    end where
  end if

  if(usrconfig%cloud_profile_pressure_on)then
    where(cloud_isuse%patch(ixO^S))
     cloud_profile(ixO^S,phys_ind%pressure_) = fprofile(ixO^S)
    end where
  else
    where(cloud_isuse%patch(ixO^S))
     cloud_profile(ixO^S,phys_ind%pressure_) = 1.0_dp
    end where
  end if
  if(usrconfig%cloud_profile_velocity_on)then
    Loop_idir_0 : do idir =1,ndir
     where(cloud_isuse%patch(ixO^S))
      cloud_profile(ixO^S,phys_ind%mom(idir)) = (1.0_dp-fprofile(ixO^S))/2.0_dp
     end where
   end do  Loop_idir_0
  else
    Loop_idir_1 : do idir =1,ndir
    where(cloud_isuse%patch(ixO^S))
      cloud_profile(ixO^S,phys_ind%mom(idir)) = 1.0_dp
    end where
  end do  Loop_idir_1
  end if
end subroutine usr_set_profile_cloud
end module mod_usr
