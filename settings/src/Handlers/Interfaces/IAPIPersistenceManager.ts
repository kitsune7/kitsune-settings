import APIInteraction from '../../API/APIInteraction'
import APIMeasurableWorkDesiredBehavior from '../../API/APIMeasurableWorkDesiredBehavior'
import APIQuadrantData from '../../API/APIQuadrantData'
import APISalesProcessSkill from '../../API/APISalesProcessSkill'
import APITeam from '../../API/APITeam'
import APIQuadrantStats from '../../API/APIQuadrantStats'
import ICurrentManagerInteractions from '../Interfaces/ICurrentManagerInteractions'
import IDBTraining from '../../DBTableInterfaces/IDBTraining'
import IDecodedAuthToken from '../../Authorizer/IDecodedAuthToken'
import IDesiredBehavior from '../../DBTableInterfaces/IDesiredBehavior'
import IFileMulter from './IFileMulter'
import IImage from '../../DBTableInterfaces/IImage'
import IImpactReport from '../../DBTableInterfaces/IImpactReport'
import IInteraction from '../../DBTableInterfaces/IInteraction'
import IManagerList from '../Interfaces/IManagerList'
import ImpactReportDTO from '../../Impact/ImpactReportDTO'
import IMetric from '../../MetricsAPI/Interfaces/IMetric'
import IPreviousManagerInteractions from '../Interfaces/IPreviousManagerInteractions'
import ISalesProcessAnalysisPM from '../../Handlers/SalesProcessAnalysis/Interfaces/ISalesProcessAnalysisPM'
import IScorecardSkillsDTO from '../../DBTableInterfaces/IScorecardSkillsDTO'
import ISFOAuthInfo from '../../DBTableInterfaces/ISFOAuthInfo'
import ITerm from '../../MetricsAPI/Interfaces/ITerm'
import ITraining from './ITraining'
import IUser from '../../DBTableInterfaces/IUser'

interface IAPIPersistenceManager extends ISalesProcessAnalysisPM {
  addNewTraining(
    trainingContent: IFileMulter,
    contentExtension: string,
    trainingThumbnail: IFileMulter,
    thumbnailExtension: string,
    trainingName: string,
    trainingDescription: string,
    tags: string,
    userId: number,
    hasThumbnail: boolean
  ): Promise<ITraining>
  addNewUser(
    accountType: string,
    companyId: number,
    crmId: string,
    email: string,
    fullName: string,
    managerId: number,
    role: string,
    roleId: number,
    startDate: string
  ): Promise<number>
  addProfilePicture(image: {
    ext: string
    name: string
    size: number
    type: string
  })
  addUsageRecord(
    description: string,
    localTime: string,
    userId: number
  ): Promise<void>
  deleteUser(
    companyId: number,
    userId: number,
    newManagerId: number,
    userIds: number[]
  ): Promise<boolean>
  emailExists(email: string): Promise<any>
  getBehaviorPerformanceByDateRange(
    userId: number,
    desiredBehaviorId: number,
    startDate: string,
    endDate: string
  ): Promise<number>
  getDesiredBehaviorTargetNameIdByUserId(
    userId: number
  ): Promise<IDesiredBehavior[]>
  getAllUsersManagedByUserId(userId: number): Promise<number[]>
  getCompanyManagers(companyId: number): Promise<object[]>
  getCompanyFrequencyById(id: number): Promise<string>
  getCompanyFrequencyByUserId(userId: number): Promise<string>
  getCompanyIdFromUserId(userId: number): Promise<number>
  getCoordinatesLastComputedDate(userId: number): Promise<string>
  getCompanyTagsByUserId(userId: number): Promise<object[]>
  getConfigurationByUserId(userId: number): Promise<object[]>
  getDesiredBehaviorsOfRolesByCompanyId(
    companyId: number,
    columns?: string[]
  ): Promise<APIMeasurableWorkDesiredBehavior[]>
  getDocumentAWSKey(userId: number, contentId: number): Promise<string>
  getImageAWSKey(userId: number, thumbnailId: number): Promise<string>
  getImageName(imageId: number): Promise<string>
  getImpactReportsByUserId(userId: number): Promise<IImpactReport[]>
  getInteractionsForUser(ownerId): Promise<APIInteraction[]>
  getManagerListUnderUser(userId: number): Promise<IManagerList[]>
  isUserManagerOfManagers(managerId: number): Promise<boolean>
  getTotalInteractionsByMonth(
    userId: number,
    year: number,
    month: number,
    date: number
  ): Promise<ICurrentManagerInteractions[]>
  getManagerNameById(managerId: number): Promise<string>
  getPreviousInteractions(
    managerId: number,
    year: number,
    month: number,
    date: number
  ): Promise<IPreviousManagerInteractions>
  getManagerOfUser(userId: number): Promise<number>
  getManagersByUserId(userId: number): Promise<object[]>
  getOrgIdByUserId(userId: number): Promise<string>
  getPersonQuadrantStats(
    userId: number,
    metricsFromMetricsApi: IMetric[],
    terms: ITerm[]
  ): Promise<APIQuadrantStats>
  getProfilePictureByUserId(userId: number): Promise<IImage>
  getQuadrantData(companyId: number): Promise<APIQuadrantData[]>
  getRolesByCompanyId(id: number, columns?: string[]): Promise<any[]>
  getSFOAuthForCompany(companyId: number): Promise<ISFOAuthInfo>
  getSkillsByDateRange(
    personId: number,
    startDate: string,
    endDate: string
  ): Promise<IScorecardSkillsDTO[]>
  getSkillsOfRolesByCompanyIdOrderByStageIndex(
    roleId: number,
    columns?: string[]
  ): Promise<APISalesProcessSkill[]>
  getTeams(companyId: number): Promise<APITeam[]>
  getTeamImpactReportByManagerId(userId: number): Promise<any>
  getTrainingsByUserId(userId: number): Promise<IDBTraining[]>
  getUserImpactReportByOwnerId(ownerId: number): Promise<ImpactReportDTO>
  getUsersByCompanyId(companyId: number): Promise<IUser[]>
  getUsersManagedByUserId(userId: number): Promise<number[]>
  getUserNameById(userId: number): Promise<string>
  getUserEmailAndNameById(
    id: number
  ): Promise<{ full_name: string; email: string }>
  getUserStartDate(userId: number): Promise<Date>
  getUsersStartDateByCompanyId(
    companyId: number
  ): Promise<{ id: number; start_date: string }[]>
  isAdmin(userId: number): Promise<boolean>
  logInteraction(
    createdById: number,
    ownerId: number,
    message: string
  ): Promise<IInteraction[]>
  reenableUser(companyId: number, userId: number): Promise<boolean>
  setUserGoal(
    decodedAuthToken: IDecodedAuthToken,
    goal: number,
    startDate: string,
    endDate: string
  ): Promise<any>
  setUserProfilePicture(imageId: number, userId: number)
  updateConfiguration(
    configuration: string,
    companyId: number
  ): Promise<object[]>
  updateUser(userId: number, params: object)
  getCompanyNameFromCompanyId(companyId: number): Promise<object[]>
}

export default IAPIPersistenceManager
